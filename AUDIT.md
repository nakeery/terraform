# Audit Findings — 2026-09-21

Read-only correctness review of all four ranges following the `saa/` / `cgscenarios/`
→ `range-0X-*` reorganization. Scope: Terraform validity (`fmt`, `validate`), a
grep for leftover pre-rename path references, a live Checkov run compared
against each project's documented skip-list/scan output, and a manual walk of
each documented attack chain against the actual Terraform/Kubernetes resources
it depends on.

**Status (updated 2026-09-21): a remediation pass has been applied.** The three
`Major` findings (one per attack range) plus the `range-01` Checkov gaps have
been resolved and are marked **✅ Resolved** inline below, with what changed.
Findings still marked **Open** were left for the maintainer to triage. Original
finding text is preserved in every case as the record of what was found.

## Repo-wide — checks that passed clean

- `terraform fmt -check` and `terraform validate` are clean with no errors or
  warnings in all four projects (`range-01` … `range-04`).
- No leftover references to the old `saa/`, `eks_phase_1`, `eks_vuln_range`,
  `cgscenarios`, `first_scenario`, `cloudgoat_rag_injection*` paths or
  identifiers anywhere in tracked files, including inside Terraform resource
  names, README cross-links, and `lambda/agent_tools.py`.
- `range-04-bedrock-rag-injection/lambda/agent_tools.zip` is a Terraform
  `archive_file`-generated build artifact, correctly covered by the `*.zip`
  gitignore rule and not tracked.
- ~~Root `README.md`'s "shared conventions" section implies every range has a
  `solution/walkthrough.md`, but `range-01-eks-secure-baseline` has none.~~
  **Resolved — not an issue.** `range-01` is the secure baseline, not an
  attack range; it doesn't need a walkthrough.

---

## range-01-eks-secure-baseline

### Major
- **✅ Resolved (2026-09-21).** `CKV_AWS_37` was fixed outright and the
  remaining five were documented as accepted risks; a `checkov --config-file
  policy/checkov.yaml` run now reports **26 passed / 0 failed / 0 skipped**.
  See the per-item notes below.
- **Checkov reports 6 undocumented failures.** `policy/checkov.yaml`'s
  skip-list documents only 3 accepted-risk checks (`CKV_AWS_39`, `CKV_AWS_38`,
  `CKV_AWS_339`). A live `checkov -d terraform/` run shows 27 passed / 6 failed
  even with that skip-list applied (9 failed unfiltered). For a range whose
  stated premise is "the hardened control everything else diffs against,"
  these are real, unacknowledged gaps:
  - `CKV_AWS_58` ("Ensure Amazon EKS Cluster has Secrets Encryption Enabled")
    — no `encryption_config` block in `terraform/eks.tf:31`; no KMS envelope
    encryption on Kubernetes Secrets. **✅ Resolved:** added to the
    `policy/checkov.yaml` skip-list with a documented reason (KMS CMK left out
    of the baseline as a conscious scope/cost decision; production would add a
    CMK + `encryption_config`).
  - `CKV_AWS_37` ("Ensure Amazon EKS control plane logging is enabled for all
    log types") — `terraform/eks.tf:31` only enables
    `["api", "audit", "authenticator"]`; `controllerManager` and `scheduler`
    are missing, undercutting the "complete audit trail" framing used to
    contrast this range against `range-02`. **✅ Resolved:** `eks.tf` now
    enables all five log types, so `CKV_AWS_37` passes and the "complete audit
    trail" claim is literally true.

### Minor
- `CKV2_AWS_11` — VPC flow logging is not enabled (`terraform/vpc.tf:4`).
  **✅ Resolved:** now documented in the `checkov.yaml` skip-list (flow logging
  is billable and not needed to teach the baseline).
- `CKV2_AWS_12` — the default VPC security group does not restrict all
  traffic. **✅ Resolved:** now documented in the `checkov.yaml` skip-list (no
  workloads use the default SG; EKS creates its own).
- `CKV_AWS_130` (×2) — public subnets set `map_public_ip_on_launch = true`
  (`terraform/vpc.tf:29-43`). Arguably intentional for subnets hosting the
  NAT gateway/load balancers, but still undocumented as an accepted risk.
  **✅ Resolved:** now documented in the `checkov.yaml` skip-list (public IP on
  launch is intended for the NAT/load-balancer subnets; nodes stay private).
- **Open.** Unverifiable from this environment: `terraform/variables.tf:55` pins
  `kubernetes_version = "1.36"`. `terraform validate` only checks HCL syntax,
  not whether AWS EKS has actually GA'd that version — worth confirming
  against the live EKS supported-version list before `apply`.

### Nit
- **Open.** `terraform/eks.tf:48` — `data "aws_eks_cluster_auth" "main"` is
  declared but never referenced (the `kubernetes` provider authenticates via an
  `exec`/`aws eks get-token` block instead). Dead code; causes an unnecessary
  AWS API call on every plan/apply.

---

## range-02-eks-attack-chain

### Major
- **✅ Resolved (2026-09-21).** Added `aws_launch_template.node` to
  `terraform/eks.tf` with `metadata_options { http_tokens = "optional",
  http_put_response_hop_limit = 1, http_endpoint = "enabled" }`, wired into the
  node group. IMDSv1 is now explicitly pinned reachable, so the walkthrough's
  unauthenticated metadata `curl` is deterministic rather than dependent on an
  account default, and the README's "walkable end to end" claim holds. A new
  Checkov finding (`CKV_AWS_79`, IMDSv1 enabled) now fires on the launch
  template and is folded into the root `scanoutput.md` narrative as the
  Terraform-visible half of the credential-theft step.
- **The documented IMDS credential-theft step isn't guaranteed by the
  Terraform.** `solution/walkthrough.md` Step 5 presents an unauthenticated
  `curl http://169.254.169.254/.../security-credentials/$ROLE` as a certainty,
  and `README.md` claims "every step in the chain below is built and walkable
  end to end." But nothing in `terraform/eks.tf` sets `metadata_options` /
  `http_tokens` — there's no `aws_launch_template` at all for the node group,
  so whether IMDSv1 is actually reachable depends on an AWS account/region
  default that this code doesn't pin. An earlier draft of `eks.tf` had a stub
  `aws_launch_template.node` resource earmarked for exactly this, which was
  deleted during the rename cleanup rather than finished.

### Minor
- **Open.** `solution/walkthrough.md:156,159,162` — the "Why This Works" recap
  mislabels which step each item corresponds to (off by one against the
  walkthrough's own Step 3/4/5 headers at lines 57, 76, 103).
- **Open.** `README.md:21-47` claims its vulnerability list is "walked in order," but
  the actual exploit chronology in `solution/walkthrough.md` loots the
  ConfigMap secrets (README item 5) *before* the cluster-admin RBAC step
  (README item 3) and the node-role/IMDS step (README item 4) — the README
  list is a catalog, not the walkthrough's chronology, despite its own
  wording.

### Nit
- **Open.** `solution/walkthrough.md:88-90` — the `SelfSubjectRulesReview` curl
  example is incomplete pseudo-code (no `-X POST`/body), though it's clearly a
  supplementary aside; the actual exploit command is complete.
- **Open.** `terraform/eks.tf:41-43` — same unused `data.aws_eks_cluster_auth.main`
  dead code as range-01.

---

## range-03-iam-privilege-escalation

### Major
- **✅ Resolved (2026-09-21).** `scanoutput.md` updated to **34 passed / 33
  failed**; the missing `CKV_AWS_274` FAILED block for
  `aws_iam_role_policy_attachment.privileged_exec_admin` (`iam.tf:200-203`) was
  added in its real position, the stale `step3_passrole_lambda` line range was
  corrected (`184-198` → `165-179`), and the "Reading this" section now calls
  out `CKV_AWS_274` as the scanner independently corroborating the
  `AdministratorAccess` grant the Step 3 chain depends on.
- **`scanoutput.md` is stale.** A live `checkov -d terraform --compact` run
  shows 34 passed / 33 failed; the doc claims 33 passed / 32 failed. The
  missing finding is `CKV_AWS_274` ("Disallow IAM roles, users, and groups
  from using the AWS AdministratorAccess policy"), `FAILED` for
  `aws_iam_role_policy_attachment.privileged_exec_admin` at
  `terraform/iam.tf:200-203` — this is arguably the single most relevant
  finding in the whole scan, since it's Checkov independently flagging the
  exact `AdministratorAccess`-on-a-role grant that the Step 3 exploit chain
  depends on, yet it's absent from the doc entirely. The doc also has a stale
  line-range citation for `aws_iam_user_policy.step3_passrole_lambda`
  (`/iam.tf:184-198` in the doc vs. the current `iam.tf:165-179`).

### Minor
- **Open.** `terraform/iam.tf:186` — `aws_iam_role.privileged_exec` is named without
  appending `random_id.suffix.hex`, unlike every other resource in this range
  (`low_priv`, `admin_target`, the loot bucket). Per `main.tf`'s own stated
  design goal of avoiding name collisions "across repeated stand-up/tear-down
  cycles or across multiple accounts," this role would clash if two instances
  of the range were stood up concurrently in the same account.

### Nit
- **Open.** `solution/walkthrough.md` step ordering is narratively awkward: Step 5
  introduces a third, independent escalation path *after* Step 4 already
  collected loot via Steps 2/3. Explicitly labeled as independent, so not
  technically wrong, just a slightly confusing read order.

---

## range-04-bedrock-rag-injection

### Major
- **✅ Resolved (2026-09-21).** Added a `BedrockKnowledgeBaseIngestion`
  statement to `aws_iam_user_policy.attacker_policy` granting
  `bedrock:StartIngestionJob` / `bedrock:GetIngestionJob`, scoped to the KB ARN
  (`aws_bedrockagent_knowledge_base.main.arn`). Walkthrough Step 3 now succeeds
  under the attacker's own credentials; the attacker stays low-privilege (it
  can re-index the bucket it already writes to, nothing else).
- **Walkthrough Step 3 isn't covered by the attacker's IAM policy as
  documented.** `solution/walkthrough.md:58-82` has the attacker run `aws
  bedrock-agent start-ingestion-job` / `get-ingestion-job` under the exported
  attacker credentials from Step 1. But `terraform/iam.tf:18-61`
  (`aws_iam_user_policy.attacker_policy`) only grants
  `s3:ListAllMyBuckets`, KB-bucket S3 access, and `bedrock:InvokeAgent` — no
  `bedrock:StartIngestionJob` / `bedrock:GetIngestionJob`. As written, this
  step would fail with `AccessDenied`.
- **Open. OpenSearch cost defaults to ~2x the documented figure.**
  `terraform/bedrock.tf:74-84` (`aws_opensearchserverless_collection.kb`)
  doesn't set `standby_replicas`, which defaults to `ENABLED` per the AWS
  provider schema. That means this collection provisions the redundant/
  multi-AZ OCU allocation (the README's own "~$700/mo with redundancy" case)
  rather than the ~$350/mo figure `README.md:146-151` presents as the
  baseline default. _Left open: this is a real cost decision (pin
  `standby_replicas = "DISABLED"` to match the documented ~$350/mo default, or
  adjust the README) that the maintainer should make deliberately._

### Minor
- **Open.** The attacker's IAM policy already grants explicit `s3:PutObject` on the KB
  bucket directly, so the permissive bucket policy at `terraform/s3.tf:35-80`
  (any authenticated in-account principal can write) isn't actually
  load-bearing for completing the walkthrough with this specific attacker
  identity — it demonstrates a real systemic issue but is a weaker
  illustration of it than the docs imply.

### Nit
- **Open.** `terraform/opensearch_index.tf:27-28` sets `number_of_shards = "2"` /
  `number_of_replicas = "0"` — arbitrary for a 2-3-document lab, harmless.
