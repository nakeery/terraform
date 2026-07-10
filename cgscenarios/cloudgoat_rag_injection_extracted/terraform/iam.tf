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
  name = "cg-attacker-${var.cgid}"
}

resource "aws_iam_access_key" "attacker" {
  user = aws_iam_user.attacker.name
}

resource "aws_iam_user_policy" "attacker_policy" {
  name = "cg-attacker-policy-${var.cgid}"
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
          IpAddress = { "aws:SourceIp" = var.cg_whitelist }
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
          IpAddress = { "aws:SourceIp" = var.cg_whitelist }
        }
      },
      {
        Sid      = "BedrockInvokeAgent"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent"]
        Resource = "*"
        Condition = {
          IpAddress = { "aws:SourceIp" = var.cg_whitelist }
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
  name = "cg-bedrock-agent-${var.cgid}"

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
  name = "cg-bedrock-agent-policy-${var.cgid}"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockModelAccess"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/*"
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
