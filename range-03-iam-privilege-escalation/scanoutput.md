# Checkov raw output - range-03-iam-privilege-escalation

Run from the repo root against the actual `.tf` files in this project with
Checkov v3.3.19. The code block below is the tool's real stdout, trimmed
only for readability, matching the precedent in the repo-root
`scanoutput.md` (the EKS ranges):

- ANSI colour escape codes stripped.
- The per-finding `Guide:` URL line (a Prisma Cloud docs link Checkov
  appends to each result) removed, to keep each finding to the 3-line
  block shape used in the EKS `scanoutput.md`.
- Windows path separators normalised (`\iam.tf` -> `/iam.tf`).

Nothing about the checks, resources or pass/fail verdicts was changed.

Unlike the older EKS scan, this Checkov version's `--compact` mode prints
only the FAILED blocks plus a summary header (it does not enumerate the 34
passing checks individually), so the pass count below comes straight from
that header line, not a manual `grep`.

---

## How to read Checkov output

Command shape:
```
checkov -d <terraform-dir> --compact
```

Each finding is a 3-line block:
```
Check: CKV_AWS_286: "Ensure IAM policies does not allow privilege escalation"
	FAILED for resource: aws_iam_user_policy.step1_self_attach
	File: /iam.tf:49-63
```
- **`Check: CKV_AWS_286`** - stable ID for one specific rule.
- **The quoted string** - human-readable description of the rule.
- **`PASSED` / `FAILED`** - did *this specific resource* satisfy the rule.
- **`resource:`** - the Terraform resource address (`type.name`).
- **`File:`** - path (relative to the scanned dir) and line range of the
  resource block.

For an **intentionally vulnerable** range, FAILED findings are the point:
they are Checkov independently confirming that the misconfigurations the
attack chain relies on are really present. The findings that map directly
to the three attack-chain steps are called out under "Reading this" below.

---

## Checkov - `range-03-iam-privilege-escalation/terraform`

**34 PASSED / 33 FAILED** (from the summary header below)

```
$ checkov -d range-03-iam-privilege-escalation/terraform --compact
```

```
terraform scan results:

Passed checks: 34, Failed checks: 33, Skipped checks: 0

Check: CKV_AWS_273: "Ensure access is controlled through SSO and not AWS IAM defined users"
	FAILED for resource: aws_iam_user.low_priv
	File: /iam.tf:11-14
Check: CKV_AWS_40: "Ensure IAM policies are attached only to groups or roles (Reducing access management complexity may in-turn reduce opportunity for a principal to inadvertently receive or retain excessive privileges.)"
	FAILED for resource: aws_iam_user_policy_attachment.low_priv_readonly
	File: /iam.tf:25-28
Check: CKV_AWS_289: "Ensure IAM policies does not allow permissions management / resource exposure without constraints"
	FAILED for resource: aws_iam_user_policy.step1_self_attach
	File: /iam.tf:49-63
Check: CKV_AWS_40: "Ensure IAM policies are attached only to groups or roles (Reducing access management complexity may in-turn reduce opportunity for a principal to inadvertently receive or retain excessive privileges.)"
	FAILED for resource: aws_iam_user_policy.step1_self_attach
	File: /iam.tf:49-63
Check: CKV_AWS_286: "Ensure IAM policies does not allow privilege escalation"
	FAILED for resource: aws_iam_user_policy.step1_self_attach
	File: /iam.tf:49-63
Check: CKV_AWS_355: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"
	FAILED for resource: aws_iam_user_policy.step1_self_attach
	File: /iam.tf:49-63
Check: CKV_AWS_273: "Ensure access is controlled through SSO and not AWS IAM defined users"
	FAILED for resource: aws_iam_user.admin_target
	File: /iam.tf:94-97
Check: CKV_AWS_287: "Ensure IAM policies does not allow credentials exposure"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_288: "Ensure IAM policies does not allow data exfiltration"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_289: "Ensure IAM policies does not allow permissions management / resource exposure without constraints"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_40: "Ensure IAM policies are attached only to groups or roles (Reducing access management complexity may in-turn reduce opportunity for a principal to inadvertently receive or retain excessive privileges.)"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_286: "Ensure IAM policies does not allow privilege escalation"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_355: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_290: "Ensure IAM policies does not allow write access without constraints"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
Check: CKV_AWS_287: "Ensure IAM policies does not allow credentials exposure"
	FAILED for resource: aws_iam_user_policy.step2_create_access_key
	File: /iam.tf:116-130
Check: CKV_AWS_289: "Ensure IAM policies does not allow permissions management / resource exposure without constraints"
	FAILED for resource: aws_iam_user_policy.step2_create_access_key
	File: /iam.tf:116-130
Check: CKV_AWS_40: "Ensure IAM policies are attached only to groups or roles (Reducing access management complexity may in-turn reduce opportunity for a principal to inadvertently receive or retain excessive privileges.)"
	FAILED for resource: aws_iam_user_policy.step2_create_access_key
	File: /iam.tf:116-130
Check: CKV_AWS_286: "Ensure IAM policies does not allow privilege escalation"
	FAILED for resource: aws_iam_user_policy.step2_create_access_key
	File: /iam.tf:116-130
Check: CKV_AWS_355: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"
	FAILED for resource: aws_iam_user_policy.step2_create_access_key
	File: /iam.tf:116-130
Check: CKV_AWS_289: "Ensure IAM policies does not allow permissions management / resource exposure without constraints"
	FAILED for resource: aws_iam_user_policy.step3_passrole_lambda
	File: /iam.tf:165-179
Check: CKV_AWS_40: "Ensure IAM policies are attached only to groups or roles (Reducing access management complexity may in-turn reduce opportunity for a principal to inadvertently receive or retain excessive privileges.)"
	FAILED for resource: aws_iam_user_policy.step3_passrole_lambda
	File: /iam.tf:165-179
Check: CKV_AWS_286: "Ensure IAM policies does not allow privilege escalation"
	FAILED for resource: aws_iam_user_policy.step3_passrole_lambda
	File: /iam.tf:165-179
Check: CKV_AWS_355: "Ensure no IAM policies documents allow "*" as a statement's resource for restrictable actions"
	FAILED for resource: aws_iam_user_policy.step3_passrole_lambda
	File: /iam.tf:165-179
Check: CKV_AWS_290: "Ensure IAM policies does not allow write access without constraints"
	FAILED for resource: aws_iam_user_policy.step3_passrole_lambda
	File: /iam.tf:165-179
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	FAILED for resource: aws_iam_role_policy_attachment.privileged_exec_admin
	File: /iam.tf:200-203
Check: CKV2_AWS_6: "Ensure that S3 bucket has a Public Access block"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV2_AWS_62: "Ensure S3 buckets should have event notifications enabled"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV_AWS_145: "Ensure that S3 buckets are encrypted with KMS by default"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV2_AWS_61: "Ensure that an S3 bucket has a lifecycle configuration"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV_AWS_18: "Ensure the S3 bucket has access logging enabled"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV_AWS_21: "Ensure all data stored in the S3 bucket have versioning enabled"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
	FAILED for resource: aws_s3_bucket.loot
	File: /s3.tf:8-11
Check: CKV2_AWS_40: "Ensure AWS IAM policy does not allow full IAM privileges"
	FAILED for resource: aws_iam_user_policy.admin_target_power
	File: /iam.tf:99-113
```

**Reading this:** the FAILED findings are Checkov confirming the attack
chain is really wired, one primitive at a time:

- **`CKV_AWS_286` (privilege escalation)** fires on `step1_self_attach`,
  `step2_create_access_key`, and `step3_passrole_lambda` - the exact three
  attack-chain steps. Checkov's own privesc detector independently
  recognises all three as escalation primitives.
- **`CKV_AWS_355` (no `"*"` resource for restrictable actions)** and
  **`CKV_AWS_289` (permissions management without constraints)** fire on
  every step policy - this is the `Resource = "*"` least-privilege
  violation each step's comment block calls out, caught mechanically.
- **`CKV_AWS_290` (write without constraints)** flags the `PassRole` step
  and the wildcarded `admin_target_power` policy.
- **`CKV_AWS_274` (no `AdministratorAccess`)** fires on
  `aws_iam_role_policy_attachment.privileged_exec_admin` - the scanner
  independently flagging the exact `AdministratorAccess`-on-a-role grant
  that the Step 3 `PassRole`-to-Lambda exploit escalates into. This is the
  payoff of the whole chain caught mechanically: pass this role to a Lambda
  and you run code as full account admin.
- **`CKV2_AWS_40` (full IAM privileges)** and **`CKV_AWS_287/288`
  (credentials exposure / data exfiltration)** flag `admin_target_power`'s
  `iam:*`/`s3:*` grant - the privileged victim Step 2 targets.
- The `aws_s3_bucket.loot` findings (no public-access block, no encryption,
  no versioning/logging) are ordinary S3 hardening gaps - not part of the
  IAM chain, but honest to leave visible: this bucket is a throwaway lab
  target, and the report shows it as such rather than hiding it.

For a secure baseline these would be failures to fix; here they are the
scanner corroborating that the lab teaches what it claims to.
