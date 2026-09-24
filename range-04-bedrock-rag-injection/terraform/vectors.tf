# -------------------------------------------------------
# S3 VECTORS VECTOR STORE
# Replaces Aurora PostgreSQL Serverless v2 + pgvector. Aurora
# took minutes to create and destroy (cluster + instance) and
# needed a settle sleep plus a chain of RDS Data API calls to
# hand-build the pgvector schema before the knowledge base could
# exist. A vector bucket + index is two API calls each way, no
# schema to build, and still bills per use with no idle floor.
# -------------------------------------------------------

resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = "range-04-kb-${random_id.suffix.hex}"
  force_destroy      = true
}

resource "aws_s3vectors_index" "kb" {
  index_name         = "bedrock-kb"
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name

  data_type       = "float32"
  dimension       = 1536 # amazon.titan-embed-text-v1 output size
  distance_metric = "cosine"

  # Bedrock writes each chunk's text and source metadata into these keys.
  # Left filterable they count against S3 Vectors' 2 KB filterable-metadata
  # cap per vector, and ingestion rejects any chunk that pushes past it.
  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }
}
