# range-04 — Bedrock RAG Injection Range

Indirect prompt injection against an Amazon Bedrock RAG assistant: a poisoned
knowledge-base document hijacks an over-permissioned agent into exfiltrating data
it should never reach.

> **Series:** [Offensive Cloud & AI Range](../README.md)  
> [range-01 · Secure Baseline](../range-01-eks-secure-baseline/README.md) → [range-02 · Attack Chain](../range-02-eks-attack-chain/README.md) → [range-03 · IAM Privesc](../range-03-iam-privilege-escalation/README.md) → **range-04 · RAG Injection**

This is the flagship AI/agentic entry in the series. It builds on the same
least-privilege lesson as [range-03](../range-03-iam-privilege-escalation/README.md):
the mechanism that turns a foothold into full data exfiltration here is an
**over-privileged Lambda execution role** backing the assistant's tools - the same
class of misconfiguration, one layer up, now reachable through natural language
instead of an API call.

**Status: complete.** The full chain is wired end to end and the Terraform
plans clean against a fresh account. The vector store scales to zero when idle -
see Cost before deploying.

> **Built on Amazon Bedrock AgentCore.** This range originally ran on Amazon
> Bedrock Agents ("Classic"), which [entered maintenance mode on 2026-07-30](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-classic-maintenance-mode.html):
> `CreateAgent` is now hard-blocked for any account without prior Bedrock Agents
> usage - which is every fresh evaluator account. The assistant has been rebuilt
> on **AgentCore** (the managed **harness** + an AgentCore **Gateway** serving the
> tools as MCP), AWS's own replacement, so the scenario deploys from declarative
> Terraform on any account. The Knowledge Base and its Aurora vector store were
> never affected by that gate and carry over unchanged.

**Difficulty**: Medium  
**Category**: AI / ML Security  
**Services**: Amazon Bedrock AgentCore (harness + gateway), Amazon Bedrock Knowledge Bases, Lambda, S3, IAM, Secrets Manager, Aurora PostgreSQL Serverless v2 (pgvector)  
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
[Bedrock Knowledge Base]  (Aurora + pgvector vector store)
    |
    | (3) Retrieved via the searchKnowledgeBase tool as RAG context
    v
[AgentCore Harness]  <-- system prompt trusts retrieved content
    |
    | (4) Injected instructions tell the assistant to call its AWS tools
    v
[AgentCore Gateway] --MCP--> [AWS-tools Lambda]  <-- overprivileged execution role
    |
    | (5) Tools read resources the assistant should never touch
    v
[Sensitive S3 Bucket]  +  [Secrets Manager]  <-- flags
```

The assistant's tools are served through an AgentCore Gateway as two MCP
targets: a **least-privilege retrieval Lambda** (`searchKnowledgeBase`, step 3)
and the **over-privileged AWS-tools Lambda** (`listBuckets` / `listObjects` /
`getObject` / `listSecrets` / `getSecret`, step 4). Injection is what bridges the
benign retrieval path onto the dangerous one.

---

## What this builds

- An S3 **knowledge-base bucket** whose policy lets any in-account principal
  write to it - the injection vector.
- A **Bedrock Knowledge Base** (Aurora PostgreSQL Serverless v2 + pgvector
  vector store) and an **AgentCore harness** (the managed agent loop) wired to
  it, with a system prompt that trusts retrieved content.
- An **AgentCore Gateway** serving the assistant's tools as MCP, with two Lambda
  targets: a **least-privilege retrieval Lambda** (`searchKnowledgeBase`) and an
  **over-privileged AWS-tools Lambda** whose execution role can read the
  sensitive bucket and Secrets Manager.
- A **low-privilege attacker user** with write access to the KB bucket and
  invoke access to the assistant (`InvokeHarness`) - and no direct access to
  the flags.

---

## The attack chain

1. **Writeable knowledge-base bucket** — any authenticated in-account principal
   can drop a document into the RAG source bucket.
2. **Ingestion trusts the source** — Bedrock ingests whatever lands there into
   the knowledge base with no content validation.
3. **Vulnerable system prompt** — the assistant is told to follow instructions
   found in retrieved documents, collapsing the trust boundary between data and
   command.
4. **Over-privileged tool role** — the AWS-tools Lambda behind the AgentCore
   Gateway can reach the sensitive bucket and Secrets Manager, so injected
   instructions execute with far more access than the assistant needs. (The
   retrieval Lambda, by contrast, is scoped to `bedrock:Retrieve` alone - the
   injection is what jumps from that safe path onto this one.)

No single named public breach maps cleanly to this exact chain; it is modeled on
documented indirect-prompt-injection technique and mapped to MITRE ATLAS (see the
walkthrough).

---

## Scenario Start

You start with:
- An IAM access key with limited permissions
- Write access to the knowledge base S3 bucket
- Invoke access to the AgentCore assistant (`bedrock-agentcore:InvokeHarness`)

You do NOT have direct access to the sensitive S3 bucket or Secrets Manager.

## Your Goal

Retrieve the two flags:
1. **Flag 1** — inside `s3://<sensitive-bucket>/confidential/customer-data.txt`
2. **Flag 2** — inside the internal API-key Secrets Manager secret

---

## Deploy

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with deployment credentials, and a recent enough CLI to
  include the `bedrock-agentcore` / `bedrock-agentcore-control` commands.
- A region where AgentCore is available (this range defaults to `us-east-1`).
  No prior Bedrock Agents usage is required - moving to AgentCore is precisely
  what sidesteps the Bedrock Agents Classic maintenance-mode gate.
- Amazon Bedrock model access enabled for `anthropic.claude-haiku-4-5-20251001-v1:0`
  and `amazon.titan-embed-text-v1` in your account. The assistant invokes Claude via
  the `us.anthropic.claude-haiku-4-5-20251001-v1:0` cross-region inference profile
  (Haiku 4.5, like Sonnet 4.5, doesn't support on-demand invocation by bare model ID),
  so grant model access in every region that profile can route to (currently us-east-1,
  us-east-2, us-west-2), not just your deployment region. (The model is the
  `bedrock_model_id` variable - swap in a Sonnet profile for more reliable injection on
  the first attempt, at higher token cost.)

```bash
cd terraform
terraform init
terraform apply -var='allowed_source_cidrs=["YOUR_IP/32"]'
```

Deployment takes approximately 10-15 minutes: Aurora cluster/instance
provisioning, then a short pause while the pgvector extension, schema,
table, and index get created via the RDS Data API before the knowledge
base can attach to them, followed by the AgentCore gateway, tool targets,
and harness.

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

**Near-zero when idle - same tier as [range-03](../range-03-iam-privilege-escalation/README.md).**
This range's vector store runs on **Aurora PostgreSQL Serverless v2**, which
scales down to **0 ACU after ~5 minutes** without a query or ingestion job and
auto-resumes in about **15 seconds** on the next one. At **0 ACU there is no
compute charge and no minimum cluster charge** - the only meter still running
is storage, at **$0.10/GB-month** (Aurora Standard, us-east-1, AWS pricing at
time of writing), which for a knowledge base this size (a handful of tiny
documents, mostly Postgres system overhead) is well under 1 GB - a few cents
a month even left standing. Active compute bills at **$0.12/ACU-hour** for
however long you're actually walking the chain, and Bedrock's own
model-invocation charges are unchanged.

The move to **Amazon Bedrock AgentCore** (see the note at the top) doesn't
change that profile. AgentCore is consumption-billed with no upfront or minimum
fee, so it adds **nothing at idle**: the harness runs inside AgentCore Runtime
($0.0895/vCPU-hour + $0.00945/GB-hour, charged only on active CPU/memory per
session - time spent waiting on the model or a tool isn't billed as CPU), and
the AgentCore Gateway adds a small per-request fee per tool call. For a lab this
size that's **pennies per full walk of the chain** and **$0 between sessions** -
dwarfed by the (unchanged) foundation-model token cost. The retired Bedrock
Agents orchestration was free, so this is a small net-new active-time meter, not
a standing one.

That's a real change from this range's original profile: it used to run on
**OpenSearch Serverless**, which held a fixed multi-OCU allocation even fully
idle - roughly $350/month at the ~2-OCU floor, the one range in the series you
genuinely couldn't leave standing. Aurora's scale-to-zero closes that gap, so
the "deploy in a sandbox account, walk it, tear it down" guidance below is now
about hygiene and credential exposure, the same reason range-03 gives it -
not a four-figure-a-year bill for forgetting a `terraform destroy`.

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
2. **Overprivileged gateway tool role** — the AWS-tools Lambda behind the
   AgentCore Gateway can read the sensitive bucket and Secrets Manager, which the
   assistant has no legitimate business need for
3. **Vulnerable system prompt** — explicitly instructs the assistant to
   follow instructions found in retrieved documents

Any one of these mitigated independently significantly reduces the risk. All
three mitigated together closes the attack path entirely.
