# -------------------------------------------------------
# OPENSEARCH SERVERLESS VECTOR INDEX
# Bedrock does NOT create the vector index for you -- the
# knowledge base creation fails with "index does not exist"
# unless the index already exists with the right mapping.
# We create it here via the opensearch provider (SigV4 auth
# against the collection endpoint).
# -------------------------------------------------------

provider "opensearch" {
  url         = aws_opensearchserverless_collection.kb.collection_endpoint
  healthcheck = false
}

# AOSS data-access and IAM grants are eventually consistent; give them time to
# propagate before the provider tries to create the index against the endpoint.
resource "time_sleep" "before_index" {
  create_duration = "60s"
  depends_on = [
    aws_opensearchserverless_collection.kb,
    aws_opensearchserverless_access_policy.kb_access
  ]
}

resource "opensearch_index" "kb" {
  name                           = "bedrock-knowledge-base-index"
  number_of_shards               = "2"
  number_of_replicas             = "0"
  index_knn                      = true
  index_knn_algo_param_ef_search = "512"
  force_destroy                  = true

  mappings = <<-EOF
    {
      "properties": {
        "bedrock-knowledge-base-default-vector": {
          "type": "knn_vector",
          "dimension": 1536,
          "method": {
            "name": "hnsw",
            "engine": "faiss",
            "space_type": "l2",
            "parameters": {
              "m": 16,
              "ef_construction": 512
            }
          }
        },
        "AMAZON_BEDROCK_TEXT_CHUNK": {
          "type": "text",
          "index": "true"
        },
        "AMAZON_BEDROCK_METADATA": {
          "type": "text",
          "index": "false"
        }
      }
    }
  EOF

  depends_on = [time_sleep.before_index]
}
