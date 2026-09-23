# =======================================================
# ATTACK CHAIN STEP 4 - THE AGENT'S TOOLS (LAMBDA GATEWAY TARGETS)
#
# Under AgentCore, an assistant reaches AWS through MCP tools served
# by an AgentCore Gateway (see bedrock.tf). Each tool is backed by a
# Lambda. We keep the original scenario's split as two separate
# targets, each with its own execution role:
#
#   1. kb_retrieval  - benign. Least privilege: it may only call
#      bedrock:Retrieve against the knowledge base.
#   2. agent_tools   - the pivot. INTENTIONALLY OVER-PRIVILEGED: its
#      execution role can read the sensitive customer bucket and
#      Secrets Manager, which a helpdesk assistant has no business
#      touching. That excess is what an indirect prompt-injection
#      payload turns into data exfiltration.
#
# The gateway invokes both using its own service role (see
# aws_iam_role.gateway); each Lambda then runs as the role below.
# =======================================================

# -------------------------------------------------------
# TOOL LAMBDA 1 - KNOWLEDGE-BASE RETRIEVAL  (least privilege)
# -------------------------------------------------------
data "archive_file" "kb_retrieval" {
  type        = "zip"
  source_file = "${path.module}/../lambda/kb_retrieval.py"
  output_path = "${path.module}/../lambda/kb_retrieval.zip"
}

resource "aws_iam_role" "kb_retrieval_lambda" {
  name = "range-04-kb-retrieval-lambda-${var.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "kb_retrieval_lambda" {
  name = "range-04-kb-retrieval-lambda-policy-${var.scenario_id}"
  role = aws_iam_role.kb_retrieval_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaLogging"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        # Least privilege: retrieval and nothing else. This is the leg of
        # the scenario that is SUPPOSED to be safe -- it cannot read the
        # sensitive bucket or any secret.
        Sid      = "KnowledgeBaseRetrieve"
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = aws_bedrockagent_knowledge_base.main.arn
      }
    ]
  })
}

resource "aws_lambda_function" "kb_retrieval" {
  function_name    = "range-04-kb-retrieval-${var.scenario_id}"
  role             = aws_iam_role.kb_retrieval_lambda.arn
  runtime          = "python3.12"
  handler          = "kb_retrieval.handler"
  filename         = data.archive_file.kb_retrieval.output_path
  source_code_hash = data.archive_file.kb_retrieval.output_base64sha256
  timeout          = 30
  description      = "ACME Corp assistant knowledge-base retrieval (AgentCore gateway target)"

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id

      # Retrieval-side flag trigger: when a retrieved passage contains this
      # marker (planted by the attacker in the KB source bucket and ingested),
      # the retrieval Lambda surfaces the flags as an extra passage. Keying on
      # ingested content forces the indirect-injection path. Flag values derive
      # from the same random_id.suffix as the authentic S3 object and secret.
      FLAG_TRIGGER_MARKER = local.flag_trigger_marker
      S3_FLAG             = "range-04-flag-${random_id.suffix.hex}"
      SECRET_FLAG         = "range-04-secret-flag-${random_id.suffix.hex}"
    }
  }
}

# -------------------------------------------------------
# TOOL LAMBDA 2 - AWS TOOLS  (INTENTIONALLY OVER-PRIVILEGED)
#
# INTENTIONAL VULNERABILITY: this Lambda's execution role can read
# the sensitive customer bucket and Secrets Manager. A helpdesk
# assistant tool has no business reading either -- which is exactly
# what the injected document weaponizes.
# -------------------------------------------------------
data "archive_file" "agent_tools" {
  type        = "zip"
  source_file = "${path.module}/../lambda/agent_tools.py"
  output_path = "${path.module}/../lambda/agent_tools.zip"
}

resource "aws_iam_role" "agent_tools_lambda" {
  name = "range-04-agent-tools-lambda-${var.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "agent_tools_lambda" {
  name = "range-04-agent-tools-lambda-policy-${var.scenario_id}"
  role = aws_iam_role.agent_tools_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "LambdaLogging"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid      = "EnumerateBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        # INTENTIONAL VULNERABILITY: read access to the sensitive
        # customer bucket. This is the pivot target the assistant
        # should never be able to reach.
        Sid    = "OverprivilegedSensitiveS3Access"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.sensitive_data.arn,
          "${aws_s3_bucket.sensitive_data.arn}/*",
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
      {
        # INTENTIONAL VULNERABILITY: no assistant tool needs
        # Secrets Manager access.
        Sid      = "OverprivilegedSecretsAccess"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:ListSecrets"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "agent_tools" {
  function_name    = "range-04-agent-tools-${var.scenario_id}"
  role             = aws_iam_role.agent_tools_lambda.arn
  runtime          = "python3.12"
  handler          = "agent_tools.handler"
  filename         = data.archive_file.agent_tools.output_path
  source_code_hash = data.archive_file.agent_tools.output_base64sha256
  timeout          = 30
  description      = "ACME Corp assistant AWS tools (AgentCore gateway target)"
}

# -------------------------------------------------------
# GATEWAY -> LAMBDA INVOKE PERMISSION
# The gateway invokes each target Lambda as its own service role. The gateway
# role's identity policy (aws_iam_role_policy.gateway_policy) grants
# lambda:InvokeFunction, which is what AWS documents for same-account targets --
# but CreateGatewayTarget validates the invoke permission at create time and can
# reject it before that inline policy propagates. These resource-based grants on
# the Lambdas make the permission unambiguous and satisfy the validation
# regardless of which side it inspects. The principal is the gateway role, since
# that is the identity that actually invokes the function.
# -------------------------------------------------------
resource "aws_lambda_permission" "gateway_invoke_kb_retrieval" {
  statement_id  = "AllowAgentCoreGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_retrieval.function_name
  principal     = aws_iam_role.gateway.arn
}

resource "aws_lambda_permission" "gateway_invoke_agent_tools" {
  statement_id  = "AllowAgentCoreGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_tools.function_name
  principal     = aws_iam_role.gateway.arn
}
