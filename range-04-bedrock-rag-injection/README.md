# range-04 — Bedrock RAG Injection Range

Indirect prompt injection against an Amazon Bedrock RAG assistant: a poisoned
knowledge-base document hijacks an over-permissioned agent into exfiltrating data
it should never reach.

> **Series:** [Offensive Cloud & AI Range](../README.md)  
> [range-01 · Secure Baseline](../range-01-eks-secure-baseline/README.md) → [range-02 · Attack Chain](../range-02-eks-attack-chain/README.md) → [range-03 · IAM Privesc](../range-03-iam-privilege-escalation/README.md) → **range-04 · RAG Injection**

This is the flagship AI/agentic entry in the series. It builds on the same
least-privilege lesson as [range-03](../range-03-iam-privilege-escalation/README.md):
the mechanism that turns a foothold into full data exfiltration here is an
**over-privileged Lambda execution role** backing the agent's tools - the same
class of misconfiguration, one layer up, now reachable through natural language
instead of an API call.

**Status: complete.** Both flags are reachable end to end. Unlike the other
ranges, this one has a real per-hour cost floor - see Cost before deploying.

**Difficulty**: Medium  
**Category**: AI / ML Security  
**Services**: Amazon Bedrock (Agents + Knowledge Bases), Lambda, S3, IAM, Secrets Manager, OpenSearch Serverless  
**MITRE ATLAS Techniques**: Indirect Prompt Injection, LLM Prompt Injection, Overprivileged IAM Role

---

## Scenario Overview

An internal AI assistant is built on Amazon Bedrock. The assistant uses a RAG
(Retrieval-Augmented Generation) knowledge base backed by an S3 bucket to answer
employee questions about company policies and IT support.

You have obtained low-privilege AWS credentials through a phishing simulation.
Your goal is to pivot from that initial foothold into sensitive AWS resources —
without ever having direct access to them.

```
[Attacker]
    |
    | (1) Plant malicious document
    v
[S3 Knowledge Base Bucket]  <-- misconfigured: any in-account principal can write
    |
    | (2) Ingested by Bedrock
    v
[Bedrock Knowledge Base]
    |
    | (3) Retrieved as RAG context
    v
[Bedrock Agent]
    |
    | (4) Injected instructions tell the agent to call its AWS tools
    v
[Action-Group Lambda]  <-- overprivileged execution role
    |
    | (5) Tools read resources the assistant should never touch
    v
[Sensitive S3 Bucket]  +  [Secrets Manager]  <-- flags
```

---

## What this builds

- An S3 **knowledge-base bucket** whose policy lets any in-account principal
  write to it - the injection vector.
- A **Bedrock Knowledge Base** (OpenSearch Serverless vector store) and a
  **Bedrock Agent** wired to it, with a system prompt that trusts retrieved
  content.
- An **action-group Lambda** exposing AWS tools to the agent, backed by an
  **over-privileged execution role** that can read the sensitive bucket and
  Secrets Manager.
- A **low-privilege attacker user** with write access to the KB bucket and
  invoke access to the agent - and no direct access to the flags.

---

## The attack chain

1. **Writeable knowledge-base bucket** — any authenticated in-account principal
   can drop a document into the RAG source bucket.
2. **Ingestion trusts the source** — Bedrock ingests whatever lands there into
   the knowledge base with no content validation.
3. **Vulnerable system prompt** — the agent is told to follow instructions found
   in retrieved documents, collapsing the trust boundary between data and command.
4. **Over-privileged action-group role** — the Lambda backing the agent's tools
   can reach the sensitive bucket and Secrets Manager, so injected instructions
   execute with far more access than the assistant needs.

No single named public breach maps cleanly to this exact chain; it is modeled on
documented indirect-prompt-injection technique and mapped to MITRE ATLAS (see the
walkthrough).

---

## Scenario Start

You start with:
- An IAM access key with limited permissions
- Write access to the knowledge base S3 bucket
- Invoke access to the Bedrock agent

You do NOT have direct access to the sensitive S3 bucket or Secrets Manager.

## Your Goal

Retrieve the two flags:
1. **Flag 1** — inside `s3://<sensitive-bucket>/confidential/customer-data.txt`
2. **Flag 2** — inside the internal API-key Secrets Manager secret

---

## Deploy

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with deployment credentials
- Amazon Bedrock model access enabled for `anthropic.claude-3-sonnet-20240229-v1:0`
  and `amazon.titan-embed-text-v1` in your account

```bash
cd terraform
terraform init
terraform apply -var='allowed_source_cidrs=["YOUR_IP/32"]'
```

Deployment takes approximately 5-10 minutes due to OpenSearch Serverless provisioning.

### Retrieve starting credentials

```bash
terraform output attacker_access_key_id
terraform output -raw attacker_secret_access_key
```

## Verify / walk the chain

Work the injection end to end using the commands in
[`solution/walkthrough.md`](solution/walkthrough.md) — plant the payload,
trigger ingestion, invoke the agent, and collect both flags.

---

## Cost

**Highest in the series, even when idle.** This range is backed by **OpenSearch
Serverless**, which bills per **OCU** (OpenSearch Compute Unit) **per hour** with
a **multi-OCU minimum allocated even when nothing is querying it** - roughly
**$350/month** at the ~2-OCU floor (us-east-1, AWS pricing at time of writing),
and about double with redundancy enabled, before any Bedrock model-invocation
charges.

That is the opposite posture from
[range-03](../range-03-iam-privilege-escalation/README.md), which is IAM +
S3 only and effectively free to leave standing. **Deploy this in a sandbox
account, walk it, and tear it down the same session** - here that guidance is
about cost, not just hygiene.

## Teardown

```bash
terraform destroy -var='allowed_source_cidrs=["YOUR_IP/32"]'
```

---

## Solution

See [`solution/walkthrough.md`](solution/walkthrough.md) — but try it yourself first.

---

## What this scenario demonstrates

1. How indirect prompt injection works against RAG-based AI systems
2. Why the trust boundary between an AI agent and its data sources matters
3. How overprivileged IAM roles amplify the blast radius of AI-based attacks
4. How to detect and mitigate prompt injection in Bedrock deployments
5. How AI infrastructure maps to MITRE ATLAS attack techniques

## Defensive Notes

The three root causes that make this scenario possible:

1. **Misconfigured S3 bucket policy** — the knowledge base bucket policy grants
   write access to any authenticated principal in the account
2. **Overprivileged action-group tool role** — the Lambda that backs the agent's
   AWS tools can read the sensitive bucket and Secrets Manager, which the
   assistant has no legitimate business need for
3. **Vulnerable agent system prompt** — explicitly instructs the agent to
   follow instructions found in retrieved documents

Any one of these mitigated independently significantly reduces the risk. All
three mitigated together closes the attack path entirely.
