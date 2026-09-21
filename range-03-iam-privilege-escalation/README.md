# range-03 — IAM Privilege Escalation Range

Three distinct AWS IAM privilege-escalation paths from a single
low-privilege foothold to full account access, built as the
identity-layer entry in the "Offensive Cloud & AI Range" series.
Where `range-01-eks-secure-baseline` shows the controls done right and
`range-02-eks-attack-chain` breaks the infrastructure layer, this range
breaks the *identity* layer - and does it with nothing but IAM and one
S3 bucket, so it costs effectively nothing to run.

> **Series:** [Offensive Cloud & AI Range](../README.md)  
> [range-01 · Secure Baseline](../range-01-eks-secure-baseline/README.md) → [range-02 · Attack Chain](../range-02-eks-attack-chain/README.md) → **range-03 · IAM Privesc** → [range-04 · RAG Injection](../range-04-bedrock-rag-injection/README.md)

**Status: complete.** All three escalation paths are built and walkable end to
end, from the low-privilege foothold to full account access.

## What this builds

- A **low-privilege attacker user** (`*-low-priv-*`) with a programmatic
  access key - the credentials you start the walkthrough with.
- `IAMReadOnlyAccess` on that user - not the vulnerability, just enough
  visibility to *enumerate* the escalation paths.
- Three inline policies on the attacker user, one per attack-chain step,
  each a documented IAM privesc primitive.
- A **higher-privileged victim user** (`*-admin-target-*`) with a
  wildcarded `iam:*`/`s3:*` policy and **no access key of its own** - the
  target of Step 2.
- A **privileged execution role** (`*-privileged-exec-role`) trusted by
  Lambda and carrying `AdministratorAccess` - the target of Step 3.
- An **S3 "loot" bucket** holding a secret only a fully-privileged
  principal should be able to read - the flag the chain reaches.

## The attack chain

Each step is a named, documented technique from **Rhino Security Labs'
"AWS IAM Privilege Escalation - Methods and Mitigation"** research. These
are general, well-documented IAM misconfigurations rather than a single
named public breach - so, in the honesty convention this series uses,
they are cited to the research source, not dressed up as a specific
incident. Walked in order:

1. **Self policy-attach** (`terraform/iam.tf`)
   The attacker's user holds `iam:AttachUserPolicy` on `Resource = "*"`.
   It attaches `AdministratorAccess` to itself in one API call and is now
   account admin. Misconfiguration: policy-attach permission not scoped to
   a safe set of policy ARNs and not fenced by a permissions boundary.

2. **Create access key for a higher-privileged user** (`terraform/iam.tf`)
   The attacker holds `iam:CreateAccessKey` on `Resource = "*"`. It mints
   a fresh long-lived key for the `admin-target` user and re-authenticates
   as that identity - no password, no MFA. Misconfiguration:
   `iam:CreateAccessKey` granted account-wide instead of scoped to the
   caller's own user ARN.

3. **PassRole + Lambda CreateFunction** (`terraform/iam.tf`)
   The attacker holds `iam:PassRole` + `lambda:CreateFunction` +
   `lambda:InvokeFunction` on `Resource = "*"`. It creates a Lambda at exploit
   time, passes the `AdministratorAccess`-carrying execution role to it, and
   invokes it to run code as that role. Misconfiguration: `iam:PassRole` with no
   `iam:PassedToService` condition and no ARN scoping.

## Deploy

```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

## Connect (as the attacker)

Pull the foothold credentials from the outputs and load them into a
dedicated CLI profile so you never mix them with your real credentials:

```bash
aws configure set aws_access_key_id     "$(terraform output -raw attacker_access_key_id)"     --profile range03-attacker
aws configure set aws_secret_access_key "$(terraform output -raw attacker_secret_access_key)" --profile range03-attacker
aws configure set region                us-east-1                                             --profile range03-attacker

# Confirm who you are
aws --profile range03-attacker sts get-caller-identity
```

## Verify / walk the chain

Confirm the foothold really is low-privileged and then escalate. Full
commands for each step are in [`solution/walkthrough.md`](solution/walkthrough.md);
the quickest smoke test that the range is live:

```bash
# You CAN enumerate users and policies...
aws --profile range03-attacker iam list-users

# ...find out which user you are (grab the name from the ARN)...
aws --profile range03-attacker sts get-caller-identity

# ...and you CAN attach admin to yourself (Step 1)
aws --profile range03-attacker iam attach-user-policy \
  --user-name <your-low-priv-user-name> \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

## Cost

**Near-zero.** This range is IAM + S3 only. IAM users, access keys,
inline policies and roles are **free**; the single S3 bucket holds one
tiny object, so you pay only for a handful of S3 API calls - a few cents
at most for an entire session. No Lambda is deployed - Step 3's attacker creates
one at exploit time - so nothing compute-bearing ever runs and there is no hourly
meter at all. This is genuinely safe to leave standing from a *billing*
standpoint (its real risk is credential exposure, not spend - see the
`warning` output).

Contrast this deliberately with **`range-04-bedrock-rag-injection`**,
the AI/agentic entry in the series. That range is backed by **OpenSearch
Serverless**, which bills per **OCU** (OpenSearch Compute Unit) **per
hour** and holds a **minimum of ~2 OCUs allocated even when completely
idle**. At roughly **$0.24 per OCU-hour** (us-east-1, AWS pricing at time
of writing) that floor works out to **~$350/month just to have it exist**,
and roughly double (~$700/month, ~4 OCUs) with redundancy enabled - before
any Bedrock model-invocation charges. That is why `range-04`'s guidance is
"stand it up, walk it, tear it down the same session" for *cost* reasons,
while `range-03` is cheap enough to leave running and only wants teardown
for *hygiene*. Same series, opposite cost postures - and worth
understanding why before you pick which one to leave up overnight.

## Teardown

```bash
cd terraform
terraform destroy
```

`force_destroy = true` on the loot bucket means `destroy` will empty and
remove it without a manual object-deletion step. Everything else is IAM,
which tears down cleanly.
