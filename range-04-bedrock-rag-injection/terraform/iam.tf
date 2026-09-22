# -------------------------------------------------------
# ATTACKER IAM USER
# Starting point for the scenario. The attacker has
# obtained these credentials via a phishing attack or
# credential leak. Low privilege - can only enumerate and
# write to the knowledge base bucket and invoke the agent.
# The permissions are attached directly to the user, so the
# provided access key works as-is (no role assumption).
# -------------------------------------------------------
resource "aws_iam_user" "attacker" {
  name = "range-04-attacker-${var.scenario_id}"
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

resource "aws_iam_user_policy" "attacker_policy" {
  name = "range-04-attacker-policy-${var.scenario_id}"
  user = aws_iam_user.attacker.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
        Condition = {
          IpAddress = { "aws:SourceIp" = var.allowed_source_cidrs }
        }
      },
      {
        Sid    = "KnowledgeBaseBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
        Condition = {
          IpAddress = { "aws:SourceIp" = var.allowed_source_cidrs }
        }
      },
      {
        Sid      = "BedrockInvokeAgent"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent"]
        Resource = "*"
        Condition = {
          IpAddress = { "aws:SourceIp" = var.allowed_source_cidrs }
        }
      },
      {
        # The attacker must be able to trigger (and poll) a knowledge-base
        # sync so Bedrock ingests the document they planted in the KB bucket
        # -- this is Step 3 of the walkthrough. Scoped to this one knowledge
        # base rather than "*": the attacker can re-index the corpus they can
        # already write to, and nothing else. Granting ingestion to a
        # principal that also has write access to the source bucket is the
        # real-world misconfiguration the range demonstrates.
        Sid    = "BedrockKnowledgeBaseIngestion"
        Effect = "Allow"
        Action = [
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob"
        ]
        Resource = aws_bedrockagent_knowledge_base.main.arn
        Condition = {
          IpAddress = { "aws:SourceIp" = var.allowed_source_cidrs }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# BEDROCK AGENT EXECUTION ROLE
# This role is scoped to least privilege for the agent
# itself: invoke the model, retrieve from the knowledge
# base, and read the KB bucket. The overprivileged access
# that makes the pivot possible lives on the action-group
# Lambda's execution role (see lambda.tf), which is what
# actually reads the sensitive bucket and Secrets Manager.
# -------------------------------------------------------
resource "aws_iam_role" "bedrock_agent" {
  name = "range-04-bedrock-agent-${var.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "bedrock.amazonaws.com" }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "bedrock_agent_policy" {
  name = "range-04-bedrock-agent-policy-${var.scenario_id}"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # var.bedrock_model_id is a cross-region inference profile (the
        # "us." prefix), not a bare on-demand model ID. Invoking it needs
        # permission on the profile ARN itself AND on the underlying
        # foundation models it can route to, which span multiple regions -
        # hence the wildcarded region on the foundation-model resource.
        Sid    = "BedrockModelAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
      },
      {
        Sid    = "KnowledgeBaseS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      },
      {
        Sid    = "BedrockKnowledgeBaseAccess"
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:RetrieveAndGenerate"
        ]
        Resource = "*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
