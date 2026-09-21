"""
Bedrock Agent action-group executor for the ACME Corp internal assistant.

This Lambda is the set of "AWS tools" the assistant can call. When the agent
decides to use a tool, Bedrock invokes this function with the tool name and
parameters; we run the corresponding AWS API call and hand the result back to
the model as tool output.

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


def _params_to_dict(parameters):
    """Bedrock passes parameters as a list of {name, type, value} objects."""
    return {p["name"]: p["value"] for p in parameters or []}


def handler(event, _context):
    action_group = event.get("actionGroup", "")
    function = event.get("function", "")
    param_map = _params_to_dict(event.get("parameters", []))

    tool = TOOLS.get(function)
    if tool is None:
        result = f"Unknown tool '{function}'."
    else:
        func, arg_names = tool
        try:
            args = [param_map.get(name) for name in arg_names]
            result = func(*args)
        except ClientError as exc:
            # Surface AWS errors as tool output so a permission gap is visible
            # to the model (and to anyone reading the scenario) rather than
            # crashing the invocation.
            result = f"AWS error calling {function}: {exc.response['Error']['Code']}"
        except Exception as exc:  # noqa: BLE001 - report anything else as text
            result = f"Error calling {function}: {exc}"

    body = result if isinstance(result, str) else json.dumps(result)

    return {
        "messageVersion": event.get("messageVersion", "1.0"),
        "response": {
            "actionGroup": action_group,
            "function": function,
            "functionResponse": {
                "responseBody": {"TEXT": {"body": body}},
            },
        },
    }
