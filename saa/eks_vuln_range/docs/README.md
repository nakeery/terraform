# EKS Vuln Range - Portfolio Project (Offensive Companion to eks_phase_1)

An intentionally-misconfigured EKS cluster, built as a sibling to
`eks_phase_1`, reusing the same file structure so the two projects can
be diffed directly against each other. Where `eks_phase_1` demonstrates
"I know how to build this securely," this project demonstrates "I know
exactly what breaks, and how, when someone doesn't."

**Status: prototype.** Several pieces are deliberately left as `TODO`
comments in the `.tf`/`.yaml` files rather than finished for you - see
each file for what's left and why. This mirrors how `eks_phase_1`
started (generated with two real bugs to find and fix), just with
different content to work through.

## The attack chain

Each step maps to a real, named incident or documented technique -
not an arbitrary "turn the security off" toggle. Walked in order:

1. **Exposed admin tooling, no auth** (`k8s/vulnerable-dashboard.yaml`)
   Internet-facing pod via `LoadBalancer`, no authentication layer.
   Modeled on the 2018 Tesla cryptomining breach (exposed, unauthenticated
   Kubernetes Dashboard).

2. **Public kubelet API** (`terraform/vpc.tf`)
   Worker nodes in public subnets + a security group open on 10250/22
   to `0.0.0.0/0`. TODO: not yet wired to the node group - see the file.

3. **Cluster-admin RBAC binding** (`k8s/vulnerable-dashboard.yaml`)
   The dashboard pod's service account is bound to `cluster-admin`.
   Compare against eks_phase_1's (unused, but present) IRSA/OIDC
   scaffolding - this is what skipping that discipline looks like.

4. **Over-privileged node IAM role** (`terraform/iam.tf`)
   `AdministratorAccess` attached to the node role, on top of the
   three policies actually required to function. Combined with #5,
   this is the same shape as the 2019 Capital One breach.

5. **IMDSv1, no hop limit** (`terraform/eks.tf`)
   TODO: launch template started but not finished - see the file's
   comments for exactly what's missing and why it matters.

6. **Flat network, no NetworkPolicy**
   Nothing here yet - this is naturally where Phase 2's Calico work
   pairs with this range: stand up the same policy tooling against
   both, and show lateral movement blocked on one side, not the other.

7. **Plaintext secrets** (`k8s/leaked-credentials.yaml`)
   Credential-shaped values in a ConfigMap instead of a Secret.

8. **No audit trail** (`terraform/eks.tf`)
   `enabled_cluster_log_types = []` - contrast against eks_phase_1's
   explicit `["api", "audit", "authenticator"]`.

## Deploy

Same shape as eks_phase_1 - see that project's README for the full
walkthrough of each command if you need a refresher.

```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

```bash
terraform output -raw configure_kubectl | bash
kubectl get nodes
kubectl apply -f ../k8s/
```

## Cost and safety - read before you leave this running

This is genuinely riskier to leave up than eks_phase_1 ever was - not
just cost, actual exposure. A real internet-facing, unauthenticated,
cluster-admin-bound pod with an over-privileged node role is not
something to let sit.

- **Deploy in an isolated/sandbox AWS account if at all possible.**
- **Stand it up, walk the chain, tear it down - same session, no exceptions.**
- Same NLB-orphan gotcha as eks_phase_1 applies: `kubectl delete -f ../k8s/`
  before `terraform destroy`.

```bash
kubectl delete -f ../k8s/
cd ../terraform
terraform destroy
```

## What's still open (your TODOs, by file)

- `terraform/vpc.tf` - wire `aws_security_group.node_vulnerable` to
  actually reach the node group (needs a launch template)
- `terraform/eks.tf` - finish `aws_launch_template.node`'s
  `metadata_options` block (IMDSv1), then reference it from
  `aws_eks_node_group.main`
- `k8s/vulnerable-dashboard.yaml` - optionally split out a dedicated
  `privileged: true` / `hostNetwork: true` pod for the container-
  breakout half of the chain
- Step 6 (flat network / no NetworkPolicy) has no dedicated file yet -
  natural pairing point once Phase 2 (Calico) exists in eks_phase_1
- KMS envelope encryption for Secrets - missing here AND in
  eks_phase_1; worth adding to both once you get to it
