# Offensive Cloud & AI Range

A four-part, progressively-built security range inspired [Rhino Security Labs' Cloudgoat project](https://github.com/rhinosecuritylabs/cloudgoat). It tells one deliberate story
across four repos: **build a cloud baseline correctly → break its
infrastructure → escalate its identity layer → attack the AI system on top of
it.** Each project pairs a documented attack chain with named real-world
parallels (or cited research where no clean public incident fits) and a
defensive-mitigations table, so the same reader can follow the thread from "how
you build it right" all the way to "how it gets taken apart."

Read the names top to bottom and the progression is the point: difficulty and
blast radius climb with each range, ending on the AI/agentic scenario.

## The series

| # | Project | What it demonstrates | Layer |
|---|---------|----------------------|-------|
| 01 | [**EKS Secure Baseline**](range-01-eks-secure-baseline/README.md) | A correctly-hardened EKS cluster: private subnets, IRSA/OIDC, least-privilege IAM, control-plane audit logging. The control everything else is diffed against. | Infrastructure (secure) |
| 02 | [**EKS Attack Chain**](range-02-eks-attack-chain/README.md) | The same cluster deliberately broken: internet-facing unauthenticated pod, `cluster-admin` binding, over-privileged node role, no audit trail. Chain mirrors the 2018 Tesla and 2019 Capital One breaches. | Infrastructure (offensive) |
| 03 | [**IAM Privilege Escalation Range**](range-03-iam-privilege-escalation/README.md) | Three distinct AWS IAM privesc paths from a low-privilege foothold to full account access. Documented Rhino Security Labs techniques. IAM + S3 only, near-zero cost. | Identity |
| 04 | [**Bedrock RAG Injection Range**](range-04-bedrock-rag-injection/README.md) | Indirect prompt injection against a Bedrock AgentCore RAG assistant: a poisoned knowledge-base document hijacks an over-permissioned agent into exfiltrating data it should never reach. Mapped to MITRE ATLAS. | AI / agentic |

## How the projects connect

- **01 → 02** are the same EKS stack, secure vs. broken, sharing a file layout
  so they diff cleanly against each other. range-02's misconfigurations are
  each the deliberate inverse of a control range-01 gets right.
- **03** moves up from infrastructure to the **identity** layer - no cluster at
  all, just IAM and S3 - showing that the account can be taken over through
  policy misconfiguration alone.
- **04** is the flagship: an AI/agentic attack chain that reuses the same IAM
  least-privilege lessons (an over-privileged Lambda execution role) as the
  mechanism that turns a prompt-injection foothold into data exfiltration.

## Shared conventions

Every range is built to the same house style so they read as one body of work:

- **Attack-chain framing.** Each misconfiguration is a numbered step with an
  `ATTACK CHAIN STEP` comment block in the Terraform explaining the real AWS/K8s
  behavior that makes it exploitable, and the least-privilege (or trust-boundary)
  violation it represents.
- **Named parallels, honestly cited.** Steps are tied to a named public incident
  where one cleanly fits (Tesla, Capital One); otherwise they cite the research
  source (e.g. Rhino Security Labs' IAM privesc catalogue) rather than inventing
  a breach.
- **A solution walkthrough** (`solution/walkthrough.md`) with real CLI commands,
  a "why this works" section, a defensive-mitigations table, and a MITRE
  ATT&CK/ATLAS mapping.
- **A safety marker.** Intentionally-vulnerable ranges tag every resource
  `Purpose = INTENTIONALLY-VULNERABLE-DO-NOT-USE-FOR-REAL-WORKLOADS` and carry a
  `warning` output. Deploy them in an isolated/sandbox account and tear them down
  the same session.

## Cost postures differ sharply - know before you deploy

The ranges are **not** uniform in cost, and the difference is worth understanding
before you deploy:

| Range | Cost posture | Why |
|-------|--------------|-----|
| 01 / 02 (EKS) | **Meaningful hourly cost** | EKS control plane, NAT/NLB, worker nodes bill by the hour - tear down after each session. |
| 03 (IAM) | **Near-zero** | IAM + S3 only; IAM is free, S3 is a few cents of API calls. Safe to leave up cost-wise (its risk is credential exposure). |
| 04 (Bedrock RAG) | **Near-zero** | Vector store is Amazon S3 Vectors - no compute and no minimum, billed only for vector storage and requests. The AgentCore harness/gateway are consumption-billed (pennies per walk, nothing at idle). Tear down is about hygiene, not a standing bill. |

## Layout

```
range-0X-<topic>/
  README.md         what it builds, the chain, deploy/verify, cost, teardown
  terraform/        infrastructure (main.tf + per-concern files)
  solution/         walkthrough.md - enumeration, exploitation, mitigations, MITRE
  k8s/ | lambda/ …  scenario-specific assets
scanoutput.md       Checkov / Kyverno scan output for the EKS ranges (01 vs 02)
```

Each project's own `README.md` is the place to start for that range.
