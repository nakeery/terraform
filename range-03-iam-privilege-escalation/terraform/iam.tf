# -------------------------------------------------------
# LOW-PRIVILEGE ATTACKER FOOTHOLD
#
# This is what you "start with" - the credentials the walkthrough
# hands you. On paper it looks harmless: read-only IAM visibility
# plus an access key. The danger is entirely in the three inline
# policies attached further down, each of which is a documented
# privilege-escalation primitive from Rhino Security Labs' "AWS
# IAM Privilege Escalation - Methods and Mitigation" research.
# -------------------------------------------------------
resource "aws_iam_user" "low_priv" {
  name          = "${local.name_prefix}-low-priv-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_iam_access_key" "low_priv" {
  user = aws_iam_user.low_priv.name
}

# Read-only IAM visibility. Not the vulnerability itself - it's what
# makes the range walkable, letting the attacker enumerate users and
# policies (iam:ListUsers, iam:ListPolicies, iam:GetPolicy...) to find
# the escalation paths below. The vuln is ADDING the write actions in
# the STEP policies on top of this, not the read-only access itself.
resource "aws_iam_user_policy_attachment" "low_priv_readonly" {
  user       = aws_iam_user.low_priv.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

# -------------------------------------------------------
# ATTACK CHAIN STEP 1 - SELF POLICY-ATTACH
#
# IAM action(s): iam:AttachUserPolicy (+ iam:ListPolicies to find a
# target policy). This is the original mechanism this lab was built
# around, and the cleanest example of the class.
#
# Why it's exploitable: a principal allowed to call
# iam:AttachUserPolicy on itself can attach ANY AWS-managed policy -
# including arn:aws:iam::aws:policy/AdministratorAccess - to its own
# user. There is no approval step and no separation of duties: the
# identity grants itself whatever it wants in a single API call and
# is now account admin.
#
# Least-privilege violation: Resource = "*". The permission to attach
# policies is not scoped to a specific, safe set of policy ARNs, and
# not fenced off with a permissions boundary. "Can manage IAM" has
# silently become "is IAM admin".
# -------------------------------------------------------
resource "aws_iam_user_policy" "step1_self_attach" {
  name = "step1-self-policy-attach"
  user = aws_iam_user.low_priv.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:AttachUserPolicy", "iam:ListPolicies"]
        Resource = "*"

        # Restrict the foothold's direct calls to the operator's IP (see
        # access.tf). This gates only the low-priv user's own calls - the
        # escalation in Steps 2-3 runs as other principals and escapes it.
        Condition = {
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# ATTACK CHAIN STEP 2 - CREATE ACCESS KEY FOR A HIGHER-PRIVILEGED USER
#
# IAM action(s): iam:CreateAccessKey (+ iam:ListUsers / iam:ListAccessKeys
# for target selection). Documented Rhino Security Labs technique
# "CreateAccessKey".
#
# Why it's exploitable: iam:CreateAccessKey lets a caller mint a brand
# new, long-lived access key FOR ANOTHER USER. If any existing user in
# the account is more privileged (here: `admin_target`, below), the
# attacker simply issues themselves that user's credentials and
# re-authenticates as them. No password, no MFA prompt, no console
# session - just a fresh programmatic credential for a privileged
# identity. It is also a quiet persistence mechanism: the new key
# survives a password reset of the target.
#
# Least-privilege violation: the action is on Resource = "*" instead
# of being scoped to the caller's OWN user ARN. iam:CreateAccessKey is
# frequently handed out so users can rotate their own keys; granted
# account-wide it becomes "impersonate anyone".
# -------------------------------------------------------

# The privileged victim. Deliberately has NO access key of its own -
# the whole point of STEP 2 is that the attacker creates one. In a
# real account this is just "some admin who only ever uses the
# console"; here a wildcarded custom policy stands in for that, which
# is closer to what you actually find in an audit than a bare
# AdministratorAccess attachment (see the STEP 1 note on why literal
# admin is the clearest teaching example but rarely the realistic one).
resource "aws_iam_user" "admin_target" {
  name          = "${local.name_prefix}-admin-target-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_iam_user_policy" "admin_target_power" {
  name = "admin-target-power"
  user = aws_iam_user.admin_target.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:*", "s3:*"]
        Resource = "*"
      }
    ]
  })
}

# The STEP 2 grant on the attacker's low-priv user.
resource "aws_iam_user_policy" "step2_create_access_key" {
  name = "step2-create-access-key"
  user = aws_iam_user.low_priv.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateAccessKey", "iam:ListUsers", "iam:ListAccessKeys"]
        Resource = "*"

        # Same operator-IP gate as Step 1 (see access.tf).
        Condition = {
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# ATTACK CHAIN STEP 3 - PASSROLE + LAMBDA CREATEFUNCTION
#
# IAM action(s): iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction.
# Documented Rhino Security Labs technique "PassExistingRoleToNewLambdaThenInvoke".
#
# Why it's exploitable: iam:PassRole is the permission to hand an
# existing IAM role to an AWS service. Paired with lambda:CreateFunction,
# an attacker who cannot use a privileged role directly can instead
# create a Lambda function, PASS the privileged role to it as the
# function's execution role, and then invoke the function to run
# arbitrary code AS that role. Compute becomes a laundering step that
# converts "I can pass this role" into "I can execute with this role's
# permissions". This is the same primitive as range-02's IMDS
# credential-theft step, one layer up the stack.
#
# The attacker holds iam:PassRole + lambda:CreateFunction +
# lambda:InvokeFunction (the inline policy below), and the target role
# `privileged_exec` carries AdministratorAccess (attached below). No
# Lambda is pre-seeded - the attacker creates one at exploit time via
# lambda:CreateFunction, which is the realistic shape of this technique
# and keeps the deployed footprint IAM + S3 only.
#
# Least-privilege violation: iam:PassRole on Resource = "*" with no
# iam:PassedToService condition. The correct posture separates "who may
# create functions" from "which roles may be passed, and to what
# service" - so that being able to create a Lambda does NOT imply being
# able to run it as an admin role. The fix is a Condition on the grant:
#   "Condition": { "StringEquals": { "iam:PassedToService": "lambda.amazonaws.com" } }
# plus scoping Resource to specific safe role ARNs.
# -------------------------------------------------------

# The STEP 3 grant on the attacker's low-priv user.
resource "aws_iam_user_policy" "step3_passrole_lambda" {
  name = "step3-passrole-lambda"
  user = aws_iam_user.low_priv.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole", "lambda:CreateFunction", "lambda:InvokeFunction"]
        Resource = "*"

        # Same operator-IP gate as Step 1 (see access.tf).
        Condition = {
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
        }
      }
    ]
  })
}

# The privileged role the attacker passes to a Lambda. Its trust policy
# lets the Lambda service assume it, and the AdministratorAccess
# attachment below makes running code as this role a full account
# takeover.
#
# Unlike the users and bucket in this range, this role deliberately keeps a
# stable, suffix-free name: the walkthrough's Step 5 commands reference it
# literally (`aws iam get-role --role-name <project>-privileged-exec-role`).
# Trade-off: two concurrent stand-ups in one account collide on this name, so
# stand up only one instance of this range per account at a time.
resource "aws_iam_role" "privileged_exec" {
  name = "${local.name_prefix}-privileged-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "privileged_exec_admin" {
  role       = aws_iam_role.privileged_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
