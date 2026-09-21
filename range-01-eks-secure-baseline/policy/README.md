# Policy-as-Code

Two layers, matching the two points where a bad config could
otherwise slip through un-reviewed:

1. **`checkov.yaml`** - Terraform-level, pre-`apply` static analysis.
   Catches bad infrastructure decisions before AWS resources exist.
2. **`kyverno/`** - Kubernetes-level, admission-time enforcement.
   Catches bad workload manifests at the moment `kubectl apply` is
   attempted, regardless of whether they came through CI or were run
   by hand.

Both layers are complete and run as-is. See the comments inside each
file for the reasoning behind specific choices.

## Layer 1 - checkov

```bash
cd range-01-eks-secure-baseline
checkov -d terraform/
```

Running it with no config file shows every finding; `checkov.yaml` then
scopes the run and documents the handful of consciously-accepted skips,
each with a reason (never suppress a finding without one).

## Layer 2 - Kyverno

Requires a live cluster with Kyverno installed
(`kubectl apply -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml`
- check their docs for the current recommended install method before
running this).

```bash
kubectl apply -f policy/kyverno/
```

All three policies ship with `validationFailureAction: Audit`, not
`Enforce` - they report violations without blocking admission. Confirm
each policy catches the intended cases on both sides before switching
to `Enforce`.

### The actual demo

Test the same three policies against both projects and compare:

```bash
# Against range-01-eks-secure-baseline's own nginx manifest - should
# pass cleanly, it already satisfies all three policies by design.
kubectl apply -f k8s/nginx-deployment.yaml

# Against range-02-eks-attack-chain's dashboard pod - should generate
# policy violations (visible via `kubectl get events` or a PolicyReport
# object once Kyverno's reporting is set up), since it runs privileged,
# sets no runAsNonRoot/readOnlyRootFilesystem, and declares no resource
# limits.
kubectl apply -f ../range-02-eks-attack-chain/k8s/vulnerable-dashboard.yaml
```

Check results with:

```bash
kubectl get polr -A          # PolicyReport objects (namespaced)
kubectl get cpolr            # ClusterPolicyReport (cluster-scoped resources)
```

That contrast - clean pass on one side, flagged violations on the
other, using the exact same policy definitions - is a stronger
demonstration than describing policy-as-code abstractly: it shows the
same enforced rule catching a real, specific mistake.
