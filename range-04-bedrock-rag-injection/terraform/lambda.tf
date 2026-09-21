# -------------------------------------------------------
# BEDROCK AGENT ACTION-GROUP TOOLS (LAMBDA)
# A Bedrock agent can only take actions through an action
# group. This Lambda IS the "AWS tools" the assistant's
# system prompt refers to. Without it the agent could not
# read S3 or Secrets Manager no matter what a document told
# it to do.
#
# INTENTIONAL VULNERABILITY: the Lambda's execution role is
# overprivileged. A helpdesk assistant tool has no business
# reading the sensitive customer bucket or Secrets Manager,
# but this role can -- which is exactly what the injected
# document weaponizes.
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
  description      = "ACME Corp assistant AWS tools (Bedrock action group executor)"
}

resource "aws_lambda_permission" "allow_bedrock" {
  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_tools.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.assistant.agent_arn
}

# The action group that exposes the Lambda tools to the agent.
resource "aws_bedrockagent_agent_action_group" "tools" {
  action_group_name          = "aws-tools"
  agent_id                   = aws_bedrockagent_agent.assistant.agent_id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true
  description                = "AWS helper tools for retrieving company resources"

  action_group_executor {
    lambda = aws_lambda_function.agent_tools.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "listBuckets"
        description = "List the names of all S3 buckets the assistant can see."
      }
      functions {
        name        = "listObjects"
        description = "List the object keys in a given S3 bucket."
        parameters {
          map_block_key = "bucketName"
          type          = "string"
          description   = "The name of the S3 bucket to list."
          required      = true
        }
      }
      functions {
        name        = "getObject"
        description = "Retrieve the text contents of an object in an S3 bucket."
        parameters {
          map_block_key = "bucketName"
          type          = "string"
          description   = "The name of the S3 bucket."
          required      = true
        }
        parameters {
          map_block_key = "objectKey"
          type          = "string"
          description   = "The key (path) of the object to retrieve."
          required      = true
        }
      }
      functions {
        name        = "listSecrets"
        description = "List the names and ARNs of secrets in AWS Secrets Manager."
      }
      functions {
        name        = "getSecret"
        description = "Retrieve the value of a secret from AWS Secrets Manager."
        parameters {
          map_block_key = "secretId"
          type          = "string"
          description   = "The name or ARN of the secret to retrieve."
          required      = true
        }
      }
    }
  }
}

# Re-prepare the agent so the DRAFT version includes both the knowledge base
# association and the action group before the "live" alias snapshots it.
# The AWS provider does not automatically re-prepare the agent when these
# separate resources change, so we do it explicitly.
resource "null_resource" "prepare_agent" {
  triggers = {
    agent_id         = aws_bedrockagent_agent.assistant.agent_id
    action_group     = aws_bedrockagent_agent_action_group.tools.action_group_id
    kb_association   = aws_bedrockagent_agent_knowledge_base_association.main.id
    instruction_hash = sha256(aws_bedrockagent_agent.assistant.instruction)
  }

  provisioner "local-exec" {
    command = "aws bedrock-agent prepare-agent --agent-id ${aws_bedrockagent_agent.assistant.agent_id} --region ${var.region}"
  }

  depends_on = [
    aws_bedrockagent_agent_action_group.tools,
    aws_bedrockagent_agent_knowledge_base_association.main
  ]
}

# Give the prepared DRAFT version time to become PREPARED before the alias
# captures it.
resource "time_sleep" "after_prepare" {
  create_duration = "30s"
  depends_on      = [null_resource.prepare_agent]
}
