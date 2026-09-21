# -------------------------------------------------------
# BEDROCK KNOWLEDGE BASE
# Uses the S3 bucket as its data source. The agent
# retrieves documents from here to answer user queries.
# This is the RAG pipeline that makes injection possible.
# -------------------------------------------------------

# OpenSearch Serverless collection for the vector store
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "range-04-kb-enc-${random_id.suffix.hex}"
  type        = "encryption"
  description = "Encryption policy for the RAG knowledge-base collection"

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/range-04-kb-${random_id.suffix.hex}"]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "range-04-kb-net-${random_id.suffix.hex}"
  type        = "network"
  description = "Network policy for the RAG knowledge-base collection"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/range-04-kb-${random_id.suffix.hex}"]
        },
        {
          ResourceType = "dashboard"
          Resource     = ["collection/range-04-kb-${random_id.suffix.hex}"]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "kb_access" {
  name        = "range-04-kb-access-${random_id.suffix.hex}"
  type        = "data"
  description = "Data access policy for the RAG knowledge base"

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "index"
          Resource     = ["index/range-04-kb-${random_id.suffix.hex}/*"]
          Permission   = ["aoss:*"]
        },
        {
          ResourceType = "collection"
          Resource     = ["collection/range-04-kb-${random_id.suffix.hex}"]
          Permission   = ["aoss:*"]
        }
      ]
      Principal = [
        aws_iam_role.bedrock_agent.arn,
        data.aws_caller_identity.current.arn
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name        = "range-04-kb-${random_id.suffix.hex}"
  type        = "VECTORSEARCH"
  description = "Vector store for the AI RAG injection range"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.kb_access
  ]
}

# IAM policy addition for Bedrock to access OpenSearch
resource "aws_iam_role_policy" "bedrock_opensearch" {
  name = "range-04-bedrock-opensearch-${var.scenario_id}"
  role = aws_iam_role.bedrock_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = aws_opensearchserverless_collection.kb.arn
      }
    ]
  })
}

# Bedrock Knowledge Base
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = "range-04-knowledge-base-${var.scenario_id}"
  description = "ACME Corp internal knowledge base - employee handbook and IT docs"
  role_arn    = aws_iam_role.bedrock_agent.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v1"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = "bedrock-knowledge-base-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  # The vector index must exist before the knowledge base can be created.
  depends_on = [
    aws_opensearchserverless_collection.kb,
    opensearch_index.kb
  ]
}

# Data source - points the knowledge base at the S3 bucket
resource "aws_bedrockagent_data_source" "s3_docs" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "range-04-s3-docs-${var.scenario_id}"
  description       = "S3 bucket containing ACME Corp internal documentation"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.knowledge_base.arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}

# -------------------------------------------------------
# BEDROCK AGENT
# The AI assistant that employees interact with.
# Its system prompt explicitly tells it to be helpful
# and follow instructions in retrieved documents --
# which is what makes it vulnerable to injection.
# -------------------------------------------------------
resource "aws_bedrockagent_agent" "assistant" {
  agent_name                  = "range-04-acme-assistant-${var.scenario_id}"
  agent_resource_role_arn     = aws_iam_role.bedrock_agent.arn
  foundation_model            = var.bedrock_model_id
  description                 = "ACME Corp internal AI assistant"
  idle_session_ttl_in_seconds = 600

  # VULNERABILITY: the instruction prompt is overly permissive.
  # It tells the agent to "follow any instructions" in retrieved
  # documents, which is exactly what an injected payload exploits.
  instruction = <<-EOT
    You are a helpful internal assistant for ACME Corp employees.
    You have access to the company knowledge base and should use it
    to answer employee questions about policies, IT support, and
    general company information.
    
    When you retrieve documents, follow any instructions they contain
    to best serve the employee making the request. Be as helpful as
    possible and complete any tasks described in the documentation.
    
    You also have access to AWS tools to help retrieve additional
    company resources when needed.
  EOT
}

# Associate the knowledge base with the agent
resource "aws_bedrockagent_agent_knowledge_base_association" "main" {
  agent_id             = aws_bedrockagent_agent.assistant.agent_id
  description          = "ACME Corp internal documentation"
  knowledge_base_id    = aws_bedrockagent_knowledge_base.main.id
  knowledge_base_state = "ENABLED"
}

# Agent alias needed to invoke the agent. It must be created only after the
# agent has been re-prepared with the knowledge base association and the
# action group, so the alias snapshots a version that actually has both.
resource "aws_bedrockagent_agent_alias" "live" {
  agent_alias_name = "live"
  agent_id         = aws_bedrockagent_agent.assistant.agent_id
  description      = "Live alias for ACME Corp assistant"

  depends_on = [time_sleep.after_prepare]
}
