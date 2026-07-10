# CloudGoat Scenario: RAG Injection via AI Knowledge Base

**Difficulty**: Medium  
**Category**: AI / ML Security  
**Services**: Amazon Bedrock (Agents + Knowledge Bases), Lambda, S3, IAM, Secrets Manager, OpenSearch Serverless  
**MITRE ATLAS Techniques**: Indirect Prompt Injection, LLM Prompt Injection, Overprivileged IAM Role

---

## Scenario Overview

ACME Corp has deployed an internal AI assistant built on Amazon Bedrock. The assistant
uses a RAG (Retrieval-Augmented Generation) knowledge base backed by an S3 bucket to
answer employee questions about company policies and IT support.

You have obtained low-privilege AWS credentials through a phishing simulation. Your goal
is to pivot from your initial foothold into sensitive AWS resources — without ever
having direct access to them.

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

## Scenario Start

You start with:
- An IAM access key with limited permissions
- Write access to the knowledge base S3 bucket
- Invoke access to the Bedrock agent

You do NOT have direct access to:
- The sensitive S3 bucket
- Secrets Manager

---

## Your Goal

Retrieve the two flags:
1. **Flag 1** — inside `s3://cg-sensitive-*/confidential/customer-data.txt`
2. **Flag 2** — inside the `cg-internal-api-key-*` Secrets Manager secret

---

## Setup

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with deployment credentials
- Amazon Bedrock model access enabled for `anthropic.claude-3-sonnet-20240229-v1:0`
  and `amazon.titan-embed-text-v1` in your account

### Deploy

```bash
cd terraform
terraform init
terraform apply -var='cg_whitelist=["YOUR_IP/32"]'
```

Deployment takes approximately 5-10 minutes due to OpenSearch Serverless provisioning.

### Retrieve starting credentials

```bash
terraform output attacker_access_key_id
terraform output -raw attacker_secret_access_key
```

---

## Teardown

```bash
terraform destroy -var='cg_whitelist=["YOUR_IP/32"]'
```

---

## Solution

See `solution/walkthrough.md` — but try it yourself first.

---

## Learning Objectives

After completing this scenario you should understand:

1. How indirect prompt injection works against RAG-based AI systems
2. Why the trust boundary between an AI agent and its data sources matters
3. How overprivileged IAM roles amplify the blast radius of AI-based attacks
4. How to detect and mitigate prompt injection in Bedrock deployments
5. How AI infrastructure maps to MITRE ATLAS attack techniques

---

## Defensive Notes

The three root causes that make this scenario possible:

1. **Misconfigured S3 bucket policy** — the knowledge base bucket policy grants
   write access to any authenticated principal in the account
2. **Overprivileged action-group tool role** — the Lambda that backs the agent's
   AWS tools can read the sensitive bucket and Secrets Manager, which the
   assistant has no legitimate business need for
3. **Vulnerable agent system prompt** — explicitly instructs the agent to
   follow instructions found in retrieved documents

Any one of these mitigated independently significantly reduces the risk.
All three mitigated together closes the attack path entirely.
