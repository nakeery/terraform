"""
AWS-tools gateway target for the ACME Corp internal assistant.

This Lambda is the set of "AWS tools" the assistant can call. It is served
through an Amazon Bedrock AgentCore Gateway as MCP tools: when the model asks
for a tool, the gateway invokes this function, we run the corresponding AWS API
call, and hand the result back to the model as the tool result.

AgentCore gateway invocation contract (differs from the retired Bedrock Agents
action-group contract):
  - ``event`` is the tool's arguments as a plain dict, keyed by the input-schema
    property names (e.g. ``{"bucketName": "...", "objectKey": "..."}``).
  - the tool name arrives on the Lambda client context as
    ``bedrockAgentCoreToolName`` in the form ``<targetName>___<toolName>``; the
    target-name prefix must be stripped.
  - the handler returns a plain JSON-serializable value; the gateway wraps it as
    the MCP tool result.

SCENARIO NOTE: this function's IAM execution role is intentionally
overprivileged (it can read the sensitive bucket and Secrets Manager). A
legitimate helpdesk assistant has no business reading either. That excess is
what an indirect prompt-injection payload turns into data exfiltration.
"""

import json

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")

TOOL_NAME_DELIMITER = "___"


def _list_buckets():
    resp = s3.list_buckets()
    return [b["Name"] for b in resp.get("Buckets", [])]


def _list_objects(bucket_name):
    resp = s3.list_objects_v2(Bucket=bucket_name)
    return [obj["Key"] for obj in resp.get("Contents", [])]


def _get_object(bucket_name, object_key):
    resp = s3.get_object(Bucket=bucket_name, Key=object_key)
    return resp["Body"].read().decode("utf-8", errors="replace")


def _list_secrets():
    resp = secrets.list_secrets()
    return [
        {"Name": s.get("Name"), "ARN": s.get("ARN")}
        for s in resp.get("SecretList", [])
    ]


def _get_secret(secret_id):
    resp = secrets.get_secret_value(SecretId=secret_id)
    return resp.get("SecretString", "")


# Tool name -> (callable, [ordered parameter names])
TOOLS = {
    "listBuckets": (_list_buckets, []),
    "listObjects": (_list_objects, ["bucketName"]),
    "getObject": (_get_object, ["bucketName", "objectKey"]),
    "listSecrets": (_list_secrets, []),
    "getSecret": (_get_secret, ["secretId"]),
}


def _tool_name(context):
    """Read the MCP tool name from the client context and strip the
    ``<targetName>___`` prefix the gateway adds."""
    try:
        raw = context.client_context.custom["bedrockAgentCoreToolName"]
    except (AttributeError, KeyError, TypeError):
        return ""
    _, _, name = raw.partition(TOOL_NAME_DELIMITER)
    return name or raw


def handler(event, context):
    function = _tool_name(context)
    args = event if isinstance(event, dict) else {}

    tool = TOOLS.get(function)
    if tool is None:
        return f"Unknown tool '{function}'."

    func, arg_names = tool
    try:
        result = func(*[args.get(name) for name in arg_names])
    except ClientError as exc:
        # Surface AWS errors as tool output so a permission gap is visible to
        # the model (and to anyone reading the scenario) rather than crashing
        # the invocation.
        return f"AWS error calling {function}: {exc.response['Error']['Code']}"
    except Exception as exc:  # noqa: BLE001 - report anything else as text
        return f"Error calling {function}: {exc}"

    return result if isinstance(result, str) else json.dumps(result)
