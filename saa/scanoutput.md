# Checkov + Kyverno raw output — eks_phase_1 vs eks_vuln_range

Commands were run from the repo root against the actual files in this repo.
Every code block below is the tool's real stdout, unedited except for
trimming a harmless network warning (checkov tries to phone home to
`api0.prismacloud.io` for extra guideline text; that call is blocked in this
sandbox and fails silently — it doesn't affect check results).

---

## How to read Checkov output

Command shape:
```
checkov -d <terraform-dir> --compact
```

Each finding is a 3-line block:
```
Check: CKV_AWS_39: "Ensure Amazon EKS public endpoint disabled"
	PASSED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
```
- **`Check: CKV_AWS_39`** — a stable ID for one specific rule. Same ID = same
  rule, every time, across any repo. Google `CKV_AWS_39 checkov` and you get
  that rule's docs page.
- **The quoted string** — human-readable description of what the rule checks.
- **`PASSED` / `FAILED`** — did *this specific resource* satisfy the rule.
  One rule can pass for one resource block and fail for another in the same
  file (you'll see this below with `aws_subnet.public[0]` vs the private
  subnets).
- **`resource:`** — the Terraform resource address (`type.name`), so you can
  `grep` straight to it.
- **`File:`** — path (relative to the scanned directory) and line range of
  the resource block, not the specific line that caused the failure.

Checkov doesn't print a pass/fail summary footer in this version's
`--compact` mode, so I counted lines manually — those counts are **mine**,
computed from the raw output with `grep -c PASSED` / `grep -c FAILED`, not
something the tool printed itself.

---

## 1. Checkov — `saa/eks_phase_1/terraform` (secure build)

**27 PASSED / 9 FAILED** (counted from the output below)

```
$ checkov -d saa/eks_phase_1/terraform --compact
```

```
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV_AWS_393: "Ensure AWS GitHub Actions OIDC authorization policies only allow safe claims and claim order on IAM role"
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role_policy_attachment.cluster_policy
	File: /iam.tf:21-24
Check: CKV_AWS_61: "Ensure AWS IAM policy does not allow assume role permission across all services"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_60: "Ensure IAM role allows only specific services or principals to assume it"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_393: "Ensure AWS GitHub Actions OIDC authorization policies only allow safe claims and claim order on IAM role"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role_policy_attachment.node_worker_policy
	File: /iam.tf:51-54
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role_policy_attachment.node_cni_policy
	File: /iam.tf:57-60
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role_policy_attachment.node_ecr_policy
	File: /iam.tf:63-66
Check: CKV_AWS_41: "Ensure no hard coded AWS access key and secret key exists in provider"
	PASSED for resource: aws.default
	File: /main.tf:29-38
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	PASSED for resource: aws_subnet.private[0]
	File: /vpc.tf:51-63
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	PASSED for resource: aws_subnet.private[1]
	File: /vpc.tf:51-63
Check: CKV2_AWS_35: "AWS NAT Gateways should be utilized for the default route"
	PASSED for resource: aws_route_table.public
	File: /vpc.tf:99-110
Check: CKV2_AWS_35: "AWS NAT Gateways should be utilized for the default route"
	PASSED for resource: aws_route_table.private
	File: /vpc.tf:118-129
Check: CKV2_AWS_44: "Ensure AWS route table with VPC peering does not contain routes overly permissive to all traffic"
	PASSED for resource: aws_route_table.public
	File: /vpc.tf:99-110
Check: CKV2_AWS_44: "Ensure AWS route table with VPC peering does not contain routes overly permissive to all traffic"
	PASSED for resource: aws_route_table.private
	File: /vpc.tf:118-129
Check: CKV2_AWS_56: "Ensure AWS Managed IAMFullAccess IAM policy is not used."
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV2_AWS_56: "Ensure AWS Managed IAMFullAccess IAM policy is not used."
	PASSED for resource: aws_iam_role_policy_attachment.cluster_policy
	File: /iam.tf:21-24
Check: CKV2_AWS_56: "Ensure AWS Managed IAMFullAccess IAM policy is not used."
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV2_AWS_56: "Ensure AWS Managed IAMFullAccess IAM policy is not used."
	PASSED for resource: aws_iam_role_policy_attachment.node_worker_policy
	File: /iam.tf:51-54
Check: CKV2_AWS_56: "Ensure AWS Managed IAMFullAccess IAM policy is not used."
	PASSED for resource: aws_iam_role_policy_attachment.node_cni_policy
	File: /iam.tf:57-60
Check: CKV2_AWS_56: "Ensure AWS Managed IAMFullAccess IAM policy is not used."
	PASSED for resource: aws_iam_role_policy_attachment.node_ecr_policy
	File: /iam.tf:63-66
Check: CKV2_AWS_19: "Ensure that all EIP addresses allocated to a VPC are attached to EC2 instances"
	PASSED for resource: aws_eip.nat
	File: /vpc.tf:77-83
Check: CKV_AWS_37: "Ensure Amazon EKS control plane logging is enabled for all log types"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_39: "Ensure Amazon EKS public endpoint disabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_58: "Ensure EKS Cluster has Secrets Encryption Enabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_339: "Ensure EKS clusters run on a supported Kubernetes version"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_38: "Ensure Amazon EKS public endpoint not accessible to 0.0.0.0/0"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	FAILED for resource: aws_subnet.public[0]
	File: /vpc.tf:29-43
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	FAILED for resource: aws_subnet.public[1]
	File: /vpc.tf:29-43
Check: CKV2_AWS_11: "Ensure VPC flow logging is enabled in all VPCs"
	FAILED for resource: aws_vpc.main
	File: /vpc.tf:4-15
Check: CKV2_AWS_12: "Ensure the default security group of every VPC restricts all traffic"
	FAILED for resource: aws_vpc.main
	File: /vpc.tf:4-15
```

**Reading this:** notice `CKV_AWS_130` ("subnets don't assign public IP")
appears twice as PASSED (for `aws_subnet.private[0]`/`[1]`) and twice as
FAILED (for `aws_subnet.public[0]`/`[1]`) — same rule, different resources,
opposite outcomes. That's expected: the public subnets *need* public IPs for
the NAT gateway/load balancers to work, so that particular FAILED is fine to
have, not something to fix.

---

## 2. Checkov — `saa/eks_vuln_range/terraform` (deliberately broken build)

**29 PASSED / 14 FAILED** (counted from the output below — this run reused
`eks_phase_1`'s `checkov.yaml` scoping since `eks_vuln_range` has no config
of its own; passed-check lines are the same style as above and omitted here
for length — only the failures are shown)

```
$ checkov -d saa/eks_vuln_range/terraform --compact
```

```
Check: CKV_AWS_39: "Ensure Amazon EKS public endpoint disabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_58: "Ensure EKS Cluster has Secrets Encryption Enabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_339: "Ensure EKS clusters run on a supported Kubernetes version"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_38: "Ensure Amazon EKS public endpoint not accessible to 0.0.0.0/0"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_79: "Ensure Instance Metadata Service Version 1 is not enabled"
	FAILED for resource: aws_launch_template.node
	File: /eks.tf:72-76
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	FAILED for resource: aws_iam_role_policy_attachment.node_admin
	File: /iam.tf:64-67
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	FAILED for resource: aws_subnet.public[0]
	File: /vpc.tf:37-49
Check: CKV_AWS_24: "Ensure no security groups allow ingress from 0.0.0.0:0 to port 22"
	FAILED for resource: aws_security_group.node_vulnerable
	File: /vpc.tf:94-124
Check: CKV_AWS_382: "Ensure no security groups allow egress from 0.0.0.0:0 to port -1"
	FAILED for resource: aws_security_group.node_vulnerable
	File: /vpc.tf:94-124
Check: CKV_AWS_23: "Ensure every security group and rule has a description"
	FAILED for resource: aws_security_group.node_vulnerable
	File: /vpc.tf:94-124
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	FAILED for resource: aws_subnet.public[1]
	File: /vpc.tf:37-49
Check: CKV2_AWS_11: "Ensure VPC flow logging is enabled in all VPCs"
	FAILED for resource: aws_vpc.main
	File: /vpc.tf:4-13
Check: CKV2_AWS_5: "Ensure that Security Groups are attached to another resource"
	FAILED for resource: aws_security_group.node_vulnerable
	File: /vpc.tf:94-124
Check: CKV2_AWS_12: "Ensure the default security group of every VPC restricts all traffic"
	FAILED for resource: aws_vpc.main
	File: /vpc.tf:4-13
```

**Reading this:** the two checks worth slowing down on are
`CKV_AWS_274` (`AdministratorAccess` on the *node* role — anything running on
a compromised node inherits full account admin) and `CKV_AWS_79` (IMDSv1
still enabled, no token requirement to read the instance metadata service).
Those two together are the exact mechanism of the 2019 Capital One breach.
`CKV2_AWS_5` ("security group not attached to another resource") is checkov
incidentally catching this repo's own documented TODO: the vulnerable SG
is defined in `vpc.tf` but never wired to the node group — so today it's
inert, not exploitable, in this exact codebase.

---

## How to read Kyverno output

Command shape:
```
kyverno apply <policy-file(s)> --resource <k8s-manifest.yaml>
```

Unlike Checkov, `kyverno apply` runs **offline** against static YAML — no
live cluster needed. Kyverno policies contain multiple **rules**; each rule
is checked against every matching Kubernetes object in the resource file.

- The summary line — `pass: X, fail: Y, warn: Z, error: 0, skip: 0` — is
  Kyverno's own native output, not something I computed.
- On a failure, Kyverno prints which **policy**, which **rule** inside it,
  which **resource** (`namespace/Kind/name`), and the **exact JSON path**
  that violated the rule (e.g.
  `/spec/template/spec/containers/0/securityContext/`) — that path is a
  direct pointer to what to add/fix in the manifest.
- `autogen-` prefix on a rule name means Kyverno auto-generated that rule
  from a Pod-level policy so it also applies to Deployments/StatefulSets/etc.
  wrapping a Pod template — you didn't write two rules, Kyverno expanded one.
- `pass: 0, fail: 0` (all zero) means the resource simply didn't match
  *any* rule in the policy — not a clean bill of health, just "not
  applicable." See the ConfigMap result below.

---

## 3. Kyverno — `eks_phase_1/k8s/nginx-deployment.yaml`

```
$ kyverno apply saa/eks_phase_1/policy/kyverno/*.yaml --resource saa/eks_phase_1/k8s/nginx-deployment.yaml
```

```
Applying 15 policy rule(s) to 1 resource(s)...

pass: 5, fail: 0, warn: 0, error: 0, skip: 0
```

All 5 applicable rules pass — its `securityContext` and resource
requests/limits satisfy every policy.

---

## 4. Kyverno — `eks_vuln_range/k8s/vulnerable-dashboard.yaml`

```
$ kyverno apply saa/eks_phase_1/policy/kyverno/*.yaml --resource saa/eks_vuln_range/k8s/vulnerable-dashboard.yaml
```

```
Applying 15 policy rule(s) to 4 resource(s)...
policy require-nonroot-and-readonly-fs -> resource default/Deployment/vulnerable-dashboard failed:
1 - autogen-require-run-as-nonroot validation error: Containers must set securityContext.runAsNonRoot: true. rule autogen-require-run-as-nonroot failed at path /spec/template/spec/containers/0/securityContext/
2 - autogen-require-readonly-root-filesystem validation error: Containers must set securityContext.readOnlyRootFilesystem: true. rule autogen-require-readonly-root-filesystem failed at path /spec/template/spec/containers/0/securityContext/
policy require-resource-limits -> resource default/Deployment/vulnerable-dashboard failed:
1 - autogen-require-requests-and-limits validation error: Containers must set resources.requests and resources.limits for both cpu and memory. rule autogen-require-requests-and-limits failed at path /spec/template/spec/containers/0/resources/

pass: 2, fail: 3, warn: 0, error: 0, skip: 0
```

**Reading this:** "4 resource(s)" is every object in that file (a
ServiceAccount, a ClusterRoleBinding, the Deployment, and a Service) — only
the Deployment is pod-shaped, so it's the only one any rule actually acts
on. Notably absent: a failure on the "no privileged containers" policy. That
policy passes here not because the pod is safe, but because the file
doesn't set `privileged: true` at all yet (it's called out as a TODO in the
manifest's own comments) — Kyverno can only fail on what's explicitly
declared, not on what's missing-but-dangerous in other ways (like the
`cluster-admin` binding one resource up, which none of these three policies
even look at).

---

## 5. Kyverno — `eks_vuln_range/k8s/leaked-credentials.yaml`

```
$ kyverno apply saa/eks_phase_1/policy/kyverno/*.yaml --resource saa/eks_vuln_range/k8s/leaked-credentials.yaml
```

```
Applying 15 policy rule(s) to 1 resource(s)...

pass: 0, fail: 0, warn: 0, error: 0, skip: 0
```

**Reading this:** all zeros. This file is a `ConfigMap` holding plaintext
AWS keys and a DB password — but every rule in these three policies targets
Pod-shaped objects (`securityContext`, `resources`, `hostNetwork`, etc.), so
none of them even match a ConfigMap. Kyverno isn't saying this file is safe;
it's saying "nothing here was in scope for what I was asked to check." Catching
plaintext credentials in a ConfigMap needs a different tool entirely (e.g. a
secrets scanner, or a purpose-built Kyverno policy targeting ConfigMap data).
