# -------------------------------------------------------
# ATTACKER IAM USER
# Starting point for the scenario. The attacker has
# obtained these credentials via a phishing attack or
# credential leak. Low privilege - can only enumerate and
# write to the knowledge base bucket and invoke the assistant.
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
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
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
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
        }
      },
      {
        # Gate the breadcrumb to the assistant only. The KB admin-notes doc
        # discloses the reference-tag convention needed to build the payload;
        # this Deny stops the attacker from reading it straight out of S3, so
        # the only way to obtain it is to ask the chatbot (retrieval runs under
        # the KB service role, not this user). Deny overrides the Allow above.
        Sid      = "DenyDirectBreadcrumbRead"
        Effect   = "Deny"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.knowledge_base.arn}/${aws_s3_object.kb_admin_notes.key}"
      },
      {
        # The assistant now runs on Amazon Bedrock AgentCore, so the
        # attacker invokes it with the InvokeHarness data-plane operation
        # (POST /harnesses/invoke) instead of the retired bedrock:InvokeAgent.
        # Authorizing that call requires BOTH IAM actions -- InvokeHarness
        # and the underlying InvokeAgentRuntime -- because an AgentCore
        # harness executes on AgentCore Runtime. Both authorize against the
        # bare harness ARN (no runtime-endpoint sub-resource is involved).
        Sid    = "AgentCoreInvokeAssistant"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeHarness",
          "bedrock-agentcore:InvokeAgentRuntime"
        ]
        Resource = aws_bedrockagentcore_harness.assistant.arn
        Condition = {
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
        }
      },
      {
        # The attacker must be able to trigger (and poll) a knowledge-base
        # sync so Bedrock ingests the document they planted in the KB bucket
        # -- this is Step 3 of the walkthrough. Scoped to this one knowledge
        # base rather than "*": the attacker can re-index the corpus they can
        # already write to, and nothing else. Granting ingestion to a
        # principal that also has write access to the source bucket is the
        # real-world misconfiguration the range demonstrates. (Ingestion is a
        # Knowledge Base API and was never affected by the Agents maintenance
        # mode that forced the AgentCore migration.)
        Sid    = "BedrockKnowledgeBaseIngestion"
        Effect = "Allow"
        Action = [
          "bedrock:StartIngestionJob",
          "bedrock:GetIngestionJob"
        ]
        Resource = aws_bedrockagent_knowledge_base.main.arn
        Condition = {
          IpAddress = { "aws:SourceIp" = local.allowed_source_cidrs }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# KNOWLEDGE BASE SERVICE ROLE
# Bedrock assumes this role to ingest documents and run
# retrieval against the S3 Vectors vector store. It is least
# privilege for that job: read the KB source bucket, invoke the
# Titan embedding model, and read/write the one vector index. It
# has NO access to the sensitive bucket or Secrets Manager.
# -------------------------------------------------------
resource "aws_iam_role" "knowledge_base" {
  name = "range-04-knowledge-base-${var.scenario_id}"

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

resource "aws_iam_role_policy" "knowledge_base_policy" {
  name = "range-04-knowledge-base-policy-${var.scenario_id}"
  role = aws_iam_role.knowledge_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # The knowledge base embeds documents (on ingestion) and queries
        # (on retrieval) with Titan Text Embeddings.
        Sid      = "TitanEmbeddingAccess"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v1"
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
        # Data-plane access to the S3 Vectors index backing the knowledge
        # base (see vectors.tf) -- write on ingestion, read on retrieval.
        Sid    = "S3VectorsAccess"
        Effect = "Allow"
        Action = [
          "s3vectors:GetIndex",
          "s3vectors:PutVectors",
          "s3vectors:GetVectors",
          "s3vectors:QueryVectors",
          "s3vectors:DeleteVectors",
          "s3vectors:ListVectors"
        ]
        Resource = aws_s3vectors_index.kb.index_arn
      }
    ]
  })
}

# -------------------------------------------------------
# AGENTCORE HARNESS EXECUTION ROLE
# The identity the managed agent loop runs as. Least privilege by
# design: invoke the foundation model and invoke the tool gateway.
# The over-privileged access that makes the pivot possible lives on
# the AWS-tools Lambda's execution role (see lambda.tf), one hop
# past this role. The extra statements (workload identity, ECR
# Public image pull, logs/metrics/traces) are the baseline every
# public-network AgentCore harness needs to start and run.
# -------------------------------------------------------
resource "aws_iam_role" "harness_exec" {
  name = "range-04-harness-exec-${var.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "bedrock-agentcore.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "harness_exec_policy" {
  name = "range-04-harness-exec-policy-${var.scenario_id}"
  role = aws_iam_role.harness_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # var.bedrock_model_id is a cross-region inference profile (the
        # "us." prefix), so permit the profile ARN and the underlying
        # foundation models it can route to across regions.
        Sid    = "BedrockModelInvocation"
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
        # SigV4 inbound gateway: the harness invokes the tool gateway as
        # itself. This is the assistant's only path to any tool.
        Sid      = "AgentCoreGatewayAccess"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:InvokeGateway"]
        Resource = aws_bedrockagentcore_gateway.tools.gateway_arn
      },
      {
        Sid    = "AgentCoreWorkloadIdentity"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForJWT"
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${var.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/harness_*"
        ]
      },
      {
        # Public-network harnesses pull their managed application image
        # from Amazon ECR Public at the start of each session.
        Sid      = "EcrPublicImagePull"
        Effect   = "Allow"
        Action   = ["ecr-public:GetAuthorizationToken", "sts:GetServiceBearerToken"]
        Resource = "*"
      },
      {
        Sid    = "ObservabilityLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"
      },
      {
        Sid    = "ObservabilityTraces"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      },
      {
        Sid      = "ObservabilityMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "bedrock-agentcore" }
        }
      }
    ]
  })
}

# -------------------------------------------------------
# AGENTCORE GATEWAY SERVICE ROLE
# The gateway assumes this role to invoke its Lambda targets. It
# holds nothing but lambda:InvokeFunction on the two tool Lambdas;
# the tools' actual power comes from each Lambda's OWN execution
# role, not from this one. (Same-account targets need only this
# identity-based grant -- a Lambda resource policy is required for
# gateway targets only when they live in a different account.)
# -------------------------------------------------------
resource "aws_iam_role" "gateway" {
  name = "range-04-gateway-${var.scenario_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "GatewayAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "bedrock-agentcore.amazonaws.com" }
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

resource "aws_iam_role_policy" "gateway_policy" {
  name = "range-04-gateway-policy-${var.scenario_id}"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeToolLambdas"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          aws_lambda_function.kb_retrieval.arn,
          aws_lambda_function.agent_tools.arn
        ]
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
