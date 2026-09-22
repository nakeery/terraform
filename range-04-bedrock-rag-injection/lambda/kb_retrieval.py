"""
Knowledge-base retrieval gateway target for the ACME Corp internal assistant.

This Lambda backs the single ``searchKnowledgeBase`` MCP tool served through the
AgentCore Gateway. It calls ``bedrock:Retrieve`` against the Aurora-backed
Bedrock Knowledge Base and returns the matching passages to the model.

This is the BENIGN, least-privilege leg of the scenario: its execution role can
do nothing but retrieve. The knowledge base itself does the vector search under
its own service role (see the knowledge base role in iam.tf); this function only
forwards the query and relays the results.

The catch is what those results can contain. Because any in-account principal
can write to the KB source bucket, an attacker can plant a document whose text
is really a set of instructions. When the assistant retrieves that document and
(per its system prompt) "follows any instructions it contains", the injection
jumps from this benign retrieval path onto the over-privileged AWS tools.

AgentCore gateway contract: ``event`` is the tool arguments dict; the tool name
is on ``context.client_context.custom['bedrockAgentCoreToolName']``; the handler
returns a plain JSON-serializable value.
"""

import json
import os

import boto3
from botocore.exceptions import ClientError

agent_runtime = boto3.client("bedrock-agent-runtime")

KNOWLEDGE_BASE_ID = os.environ["KNOWLEDGE_BASE_ID"]


def handler(event, _context):
    args = event if isinstance(event, dict) else {}
    query = args.get("query") or ""
    if not query:
        return "No query provided."

    try:
        resp = agent_runtime.retrieve(
            knowledgeBaseId=KNOWLEDGE_BASE_ID,
            retrievalQuery={"text": query},
        )
    except ClientError as exc:
        return f"AWS error calling Retrieve: {exc.response['Error']['Code']}"

    passages = [
        r.get("content", {}).get("text", "")
        for r in resp.get("retrievalResults", [])
    ]
    return json.dumps({"passages": passages})
