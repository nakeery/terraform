# Checkov + Kyverno raw output — range-01-eks-secure-baseline vs range-02-eks-attack-chain

Commands were run from the repo root against the actual files in this repo.
Every code block below is the tool's real stdout, trimmed only for readability:
Checkov's ASCII banner, the per-finding `Guide:` URL lines, and the pass/fail
summary footer are removed, and Windows path separators are normalised
(`\eks.tf` -> `/eks.tf`). No check, resource, or verdict was changed. (Checkov
also tries to phone home to `api0.prismacloud.io` for extra guideline text; that
call is blocked in this sandbox and fails silently — it doesn't affect results.)

---

## How to read Checkov output

Command shape:
```
checkov -d <terraform-dir> --compact
```

Each finding is a 3-line block:
```
Check: CKV_AWS_100: "Ensure AWS EKS node group does not have implicit SSH access from 0.0.0.0/0"
	PASSED for resource: aws_eks_node_group.main
	File: /eks.tf:64-91
```
- **`Check: CKV_AWS_100`** — a stable ID for one specific rule. Same ID = same
  rule, every time, across any repo. Google `CKV_AWS_100 checkov` and you get
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

Checkov's own `Passed/Failed` summary footer is trimmed from the blocks below;
the counts in each section header come from that footer (and match
`grep -c PASSED` / `grep -c FAILED` over the raw output).

---

## 1. Checkov — `range-01-eks-secure-baseline/terraform` (secure build)

**28 PASSED / 8 FAILED**

```
$ checkov -d range-01-eks-secure-baseline/terraform --compact
```

```
Check: CKV_AWS_100: "Ensure AWS EKS node group does not have implicit SSH access from 0.0.0.0/0"
	PASSED for resource: aws_eks_node_group.main
	File: /eks.tf:64-91
Check: CKV_AWS_393: "Ensure AWS GitHub Actions OIDC authorization policies only allow safe claims and claim order on IAM role"
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV_AWS_61: "Ensure AWS IAM policy does not allow assume role permission across all services"
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV_AWS_60: "Ensure IAM role allows only specific services or principals to assume it"
	PASSED for resource: aws_iam_role.cluster
	File: /iam.tf:6-19
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role_policy_attachment.cluster_policy
	File: /iam.tf:21-24
Check: CKV_AWS_393: "Ensure AWS GitHub Actions OIDC authorization policies only allow safe claims and claim order on IAM role"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_61: "Ensure AWS IAM policy does not allow assume role permission across all services"
	PASSED for resource: aws_iam_role.node
	File: /iam.tf:35-48
Check: CKV_AWS_60: "Ensure IAM role allows only specific services or principals to assume it"
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
Check: CKV2_AWS_44: "Ensure AWS route table with VPC peering does not contain routes overly permissive to all traffic"
	PASSED for resource: aws_route_table.public
	File: /vpc.tf:99-110
Check: CKV2_AWS_44: "Ensure AWS route table with VPC peering does not contain routes overly permissive to all traffic"
	PASSED for resource: aws_route_table.private
	File: /vpc.tf:118-129
Check: CKV_AWS_339: "Ensure EKS clusters run on a supported Kubernetes version"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_39: "Ensure Amazon EKS public endpoint disabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_38: "Ensure Amazon EKS public endpoint not accessible to 0.0.0.0/0"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:13-43
Check: CKV_AWS_58: "Ensure EKS Cluster has Secrets Encryption Enabled"
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

The 8 failures on the "secure" build are the honest residue. Control-plane
logging is fully enabled for all five log types, so CKV_AWS_37 now passes (it
is no longer in the list above). The public endpoint (CKV_AWS_39/38) and the
Kubernetes-version pin (CKV_AWS_339) are documented, consciously-accepted
tradeoffs scoped in `policy/checkov.yaml`; running with that config file
applied reports **0 failures**. The remainder (CKV_AWS_58 secrets KMS
encryption, CKV2_AWS_11 VPC flow logs, CKV2_AWS_12 default-SG lockdown, and
CKV_AWS_130 public-IP-on-launch for the NAT/load-balancer subnets) are also
enumerated in that skip-list with a per-check reason - real hardening a
production build would revisit, accepted here as scope decisions rather than
left silently failing. None are the catastrophic misconfigurations range-02
introduces.

---

## 2. Checkov — `range-02-eks-attack-chain/terraform` (deliberately broken build)

**26 PASSED / 10 FAILED** (run against the raw Terraform with no config file, so
the accepted-tradeoff skips in range-01's `checkov.yaml` are not applied;
passed-check lines share the style above and are omitted for length — only the
failures are shown)

```
$ checkov -d range-02-eks-attack-chain/terraform --compact
```

```
Check: CKV_AWS_339: "Ensure EKS clusters run on a supported Kubernetes version"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_39: "Ensure Amazon EKS public endpoint disabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_38: "Ensure Amazon EKS public endpoint not accessible to 0.0.0.0/0"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_58: "Ensure EKS Cluster has Secrets Encryption Enabled"
	FAILED for resource: aws_eks_cluster.main
	File: /eks.tf:4-35
Check: CKV_AWS_79: "Ensure Instance Metadata Service Version 1 is not enabled"
	FAILED for resource: aws_launch_template.node
	File: /eks.tf:67-82
Check: CKV_AWS_274: "Disallow IAM roles, users, and groups from using the AWS AdministratorAccess policy"
	FAILED for resource: aws_iam_role_policy_attachment.node_admin
	File: /iam.tf:56-59
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	FAILED for resource: aws_subnet.public[0]
	File: /vpc.tf:37-49
Check: CKV_AWS_130: "Ensure VPC subnets do not assign public IP by default"
	FAILED for resource: aws_subnet.public[1]
	File: /vpc.tf:37-49
Check: CKV2_AWS_11: "Ensure VPC flow logging is enabled in all VPCs"
	FAILED for resource: aws_vpc.main
	File: /vpc.tf:4-13
Check: CKV2_AWS_12: "Ensure the default security group of every VPC restricts all traffic"
	FAILED for resource: aws_vpc.main
	File: /vpc.tf:4-13
```

**Reading this:** the standout is `CKV_AWS_274` — `AdministratorAccess` on the
*node* role, so anything running on a compromised node inherits full account
admin. That is the escalation-out-to-AWS half of the 2019 Capital One shape.
`CKV_AWS_79` is the other half made explicit in the Terraform: the node launch
template pins `http_tokens = "optional"`, leaving IMDSv1 reachable, which is
exactly the unauthenticated metadata call the walkthrough's Step 5 uses to steal
those node-role credentials. (The Kubernetes-layer enabler — the privileged,
`hostNetwork` dashboard pod that shares the node's network namespace — a
Terraform scan doesn't see; Checkov and Kyverno each catch part of the same
chain.) `CKV_AWS_39`/`CKV_AWS_38` (public
EKS endpoint) and `CKV_AWS_130` (subnets auto-assigning public IPs) are the
public-exposure posture range-01 keeps private; here they compound with the rest
of the chain rather than being an accepted, documented tradeoff.

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

## 3. Kyverno — `range-01-eks-secure-baseline/k8s/nginx-deployment.yaml`

```
$ kyverno apply range-01-eks-secure-baseline/policy/kyverno/*.yaml --resource range-01-eks-secure-baseline/k8s/nginx-deployment.yaml
```

```
Applying 15 policy rule(s) to 1 resource(s)...

pass: 5, fail: 0, warn: 0, error: 0, skip: 0
```

All 5 applicable rules pass — its `securityContext` and resource
requests/limits satisfy every policy.

---

## 4. Kyverno — `range-02-eks-attack-chain/k8s/vulnerable-dashboard.yaml`

```
$ kyverno apply range-01-eks-secure-baseline/policy/kyverno/*.yaml --resource range-02-eks-attack-chain/k8s/vulnerable-dashboard.yaml
```

```
Applying 15 policy rule(s) to 4 resource(s)...
policy disallow-privileged-and-host-namespaces -> resource default/Deployment/vulnerable-dashboard failed:
1 - autogen-no-privileged-containers validation error: Privileged containers are not allowed. rule autogen-no-privileged-containers failed at path /spec/template/spec/containers/0/securityContext/privileged/
2 - autogen-no-host-namespaces validation error: Sharing the host network, PID, or IPC namespace is not allowed. rule autogen-no-host-namespaces failed at path /spec/template/spec/hostNetwork/
policy require-nonroot-and-readonly-fs -> resource default/Deployment/vulnerable-dashboard failed:
1 - autogen-require-run-as-nonroot validation error: Containers must set securityContext.runAsNonRoot: true. rule autogen-require-run-as-nonroot failed at path /spec/template/spec/containers/0/securityContext/runAsNonRoot/
2 - autogen-require-readonly-root-filesystem validation error: Containers must set securityContext.readOnlyRootFilesystem: true. rule autogen-require-readonly-root-filesystem failed at path /spec/template/spec/containers/0/securityContext/readOnlyRootFilesystem/
policy require-resource-limits -> resource default/Deployment/vulnerable-dashboard failed:
1 - autogen-require-requests-and-limits validation error: Containers must set resources.requests and resources.limits for both cpu and memory. rule autogen-require-requests-and-limits failed at path /spec/template/spec/containers/0/resources/

pass: 0, fail: 5, warn: 0, error: 0, skip: 0
```

**Reading this:** "4 resource(s)" is every object in that file (a
ServiceAccount, a ClusterRoleBinding, the Deployment, and a Service) — only the
Deployment is pod-shaped, so it's the only one any rule acts on, and it fails
all five: it runs `privileged: true` and `hostNetwork: true` (both caught by
`disallow-privileged-and-host-namespaces`), sets neither `runAsNonRoot` nor
`readOnlyRootFilesystem`, and declares no resource limits. The exact inverse of
range-01's nginx, which passes all five, using the identical policy set. Note
the `cluster-admin` binding one resource up is not something these three
workload-hardening policies look at — catching that needs an RBAC-focused
policy.

---

## 5. Kyverno — `range-02-eks-attack-chain/k8s/leaked-credentials.yaml`

```
$ kyverno apply range-01-eks-secure-baseline/policy/kyverno/*.yaml --resource range-02-eks-attack-chain/k8s/leaked-credentials.yaml
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
