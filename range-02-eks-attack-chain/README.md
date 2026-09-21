# range-02 — EKS Attack Chain

An intentionally-misconfigured EKS cluster, the offensive companion to
[range-01](../range-01-eks-secure-baseline/README.md) — reusing the same
file structure so the two diff directly against each other. Where range-01
demonstrates "I know how to build this securely," this project demonstrates "I
know exactly what breaks, and how, when someone doesn't."

> **Series:** [Offensive Cloud & AI Range](../README.md)  
> [range-01 · Secure Baseline](../range-01-eks-secure-baseline/README.md) → **range-02 · Attack Chain** → [range-03 · IAM Privesc](../range-03-iam-privilege-escalation/README.md) → [range-04 · RAG Injection](../range-04-bedrock-rag-injection/README.md)

**Status: complete.** Every step in the chain below is built and walkable end to
end; the full exploitation path is in
[`solution/walkthrough.md`](solution/walkthrough.md).

## The attack chain

Each step maps to a real, named incident or documented technique -
not an arbitrary "turn the security off" toggle. Walked in order:

1. **Exposed admin tooling, no auth** (`k8s/vulnerable-dashboard.yaml`)
   Internet-facing pod via `LoadBalancer`, no authentication layer.
   Modeled on the 2018 Tesla cryptomining breach (exposed, unauthenticated
   Kubernetes Dashboard).

2. **Privileged, host-networked pod** (`k8s/vulnerable-dashboard.yaml`)
   The pod runs `privileged: true` with `hostNetwork: true` and no
   securityContext - container isolation is gone, and the pod shares the node's
   network namespace, so it can reach the node filesystem and the node's IMDS.

3. **Cluster-admin RBAC binding** (`k8s/vulnerable-dashboard.yaml`)
   The pod's service account is bound to `cluster-admin`, so code execution in
   the pod is full control of the cluster - every Secret in every namespace.

4. **Over-privileged node IAM role** (`terraform/iam.tf`)
   `AdministratorAccess` attached to the node role, on top of the three policies
   actually required to function. Reached through the node's IMDS from the
   host-networked pod, this is the same shape as the 2019 Capital One breach.

5. **Plaintext secrets** (`k8s/leaked-credentials.yaml`)
   Credential-shaped values in a ConfigMap instead of a Secret - readable with
   minimal RBAC and unencrypted at rest.

6. **No audit trail** (`terraform/eks.tf`)
   `enabled_cluster_log_types = []` - contrast against range-01-eks-secure-baseline's
   explicit `["api", "audit", "authenticator"]`. None of the steps above leave a
   control-plane audit record.

## Deploy

Same shape as range-01-eks-secure-baseline - see that project's README for the full
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

This is genuinely riskier to leave up than range-01-eks-secure-baseline ever was - not
just cost, actual exposure. A real internet-facing, unauthenticated,
cluster-admin-bound pod with an over-privileged node role is not
something to let sit.

- **Deploy in an isolated/sandbox AWS account if at all possible.**
- **Stand it up, walk the chain, tear it down - same session, no exceptions.**
- Same NLB-orphan gotcha as range-01-eks-secure-baseline applies: `kubectl delete -f ../k8s/`
  before `terraform destroy`.

```bash
kubectl delete -f ../k8s/
cd ../terraform
terraform destroy
```
