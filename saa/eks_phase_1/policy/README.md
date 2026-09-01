# Policy-as-Code Prototypes (Phase 3 preview)

Two layers, matching the two points where a bad config could
otherwise slip through un-reviewed:

1. **`checkov.yaml`** - Terraform-level, pre-`apply` static analysis.
   Catches bad infrastructure decisions before AWS resources exist.
2. **`kyverno/`** - Kubernetes-level, admission-time enforcement.
   Catches bad workload manifests at the moment `kubectl apply` is
   attempted, regardless of whether they came through CI or were run
   by hand.

Status: **prototype.** The Kyverno policies are complete and should
run as-is; `checkov.yaml` has a TODO for you to fill in after your
first run. See the comments inside each file for the reasoning behind
specific choices.

## Layer 1 - checkov

```bash
cd saa/eks_phase_1
checkov -d terraform/
```

Run it once with no config file first and read the findings before
touching `checkov.yaml` - see that file's own comments for what to do
with what you find (short version: don't suppress anything without a
documented reason).

## Layer 2 - Kyverno

Requires a live cluster with Kyverno installed
(`kubectl apply -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml`
- check their docs for the current recommended install method before
running this).

```bash
kubectl apply -f policy/kyverno/
```

All three policies ship with `validationFailureAction: Audit`, not
`Enforce` - they'll report violations without blocking anything yet.
That's deliberate: confirm each policy actually catches what you
expect on both sides before switching to `Enforce`.

### The actual demo

Test the same three policies against both projects and compare:

```bash
# Against eks_phase_1's own nginx manifest - should pass cleanly,
# it already satisfies all three policies by design.
kubectl apply -f ../eks_phase_1/k8s/nginx-deployment.yaml

# Against eks_vuln_range's dashboard pod - should generate policy
# violations (visible via `kubectl get events` or a PolicyReport
# object once Kyverno's reporting is set up), since it sets no
# securityContext and no resource limits at all.
kubectl apply -f ../eks_vuln_range/k8s/vulnerable-dashboard.yaml
```

Check results with:

```bash
kubectl get polr -A          # PolicyReport objects (namespaced)
kubectl get cpolr            # ClusterPolicyReport (cluster-scoped resources)
```

That contrast - clean pass on one side, flagged violations on the
other, using the exact same policy definitions - is the concrete
artifact worth screenshotting for a portfolio write-up. It's a
stronger demonstration than describing policy-as-code abstractly:
it shows the same enforced rule catching a real, specific mistake.

## What's next

Once both layers are tested manually and you're comfortable with
them, Phase 3 proper is wiring `checkov` into an actual CI pipeline
(GitHub Actions or Jenkins - still an open decision) so it runs
automatically on every PR, rather than something you remember to run
by hand.
