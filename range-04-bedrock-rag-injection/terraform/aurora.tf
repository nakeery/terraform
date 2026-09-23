# -------------------------------------------------------
# AURORA POSTGRESQL SERVERLESS V2 VECTOR STORE
# Bedrock does NOT create the pgvector schema for you -- the
# knowledge base creation fails unless the extension, schema,
# table, and index already exist with the right shape. We
# create them here via the RDS Data API, so the cluster never
# needs to accept a direct inbound DB connection from wherever
# `terraform apply` runs.
#
# Replaces OpenSearch Serverless: that backend held a fixed
# ~2 OCU floor even fully idle (~$350/mo). Aurora Serverless v2
# scales to 0 ACU after 5 minutes idle and auto-resumes in
# ~15s on the next query or ingestion job, so this range now
# costs close to nothing between sessions -- storage only.
# -------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# No ingress rules at all: every interaction with this cluster goes through
# the RDS Data API (IAM + Secrets Manager auth), never a direct :5432
# connection, so the security group has nothing to open.
resource "aws_security_group" "aurora" {
  name        = "range-04-aurora-${random_id.suffix.hex}"
  description = "Aurora RAG vector store - Data API only, no inbound rules"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_db_subnet_group" "aurora" {
  name       = "range-04-aurora-${random_id.suffix.hex}"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_rds_cluster" "kb" {
  cluster_identifier = "range-04-kb-${random_id.suffix.hex}"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  # Pin a version that supports both pgvector HNSW (>= 0.5.0) and
  # scale-to-zero ACUs. If this exact patch isn't offered in your region,
  # check `aws rds describe-db-engine-versions --engine aurora-postgresql`
  # and bump it.
  engine_version = "16.14"
  database_name  = "bedrockkb"

  master_username             = "bedrockadmin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  enable_http_endpoint = true # RDS Data API
  storage_encrypted    = true
  apply_immediately    = true
  skip_final_snapshot  = true

  serverlessv2_scaling_configuration {
    min_capacity             = 0
    max_capacity             = 1
    seconds_until_auto_pause = 300
  }
}

resource "aws_rds_cluster_instance" "kb" {
  cluster_identifier = aws_rds_cluster.kb.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.kb.engine
  engine_version     = aws_rds_cluster.kb.engine_version
}

# Data API + Secrets Manager access are eventually consistent right after
# cluster creation, same reasoning as the old AOSS setup this replaced --
# give the cluster a minute to settle before the first Data API call.
resource "time_sleep" "before_pgvector_setup" {
  create_duration = "60s"
  depends_on = [
    aws_rds_cluster_instance.kb
  ]
}

locals {
  rds_data_common_args = "--resource-arn ${aws_rds_cluster.kb.arn} --secret-arn ${aws_rds_cluster.kb.master_user_secret[0].secret_arn} --database ${aws_rds_cluster.kb.database_name}"
}

resource "null_resource" "pgvector_extension" {
  provisioner "local-exec" {
    command = "aws rds-data execute-statement ${local.rds_data_common_args} --sql \"CREATE EXTENSION IF NOT EXISTS vector;\""
  }
  depends_on = [time_sleep.before_pgvector_setup]
}

resource "null_resource" "pgvector_schema" {
  provisioner "local-exec" {
    command = "aws rds-data execute-statement ${local.rds_data_common_args} --sql \"CREATE SCHEMA IF NOT EXISTS bedrock_integration;\""
  }
  depends_on = [null_resource.pgvector_extension]
}

resource "null_resource" "pgvector_table" {
  provisioner "local-exec" {
    command = "aws rds-data execute-statement ${local.rds_data_common_args} --sql \"CREATE TABLE IF NOT EXISTS bedrock_integration.bedrock_kb (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), embedding vector(1536), chunks text, metadata json);\""
  }
  depends_on = [null_resource.pgvector_schema]
}

resource "null_resource" "pgvector_index" {
  provisioner "local-exec" {
    command = "aws rds-data execute-statement ${local.rds_data_common_args} --sql \"CREATE INDEX IF NOT EXISTS bedrock_kb_embedding_idx ON bedrock_integration.bedrock_kb USING hnsw (embedding vector_cosine_ops);\""
  }
  depends_on = [null_resource.pgvector_table]
}

# IAM addition for the knowledge base service role to reach the Aurora vector
# store via the RDS Data API. Attached here (next to the cluster it grants
# access to) rather than in iam.tf so the Aurora-specific permissions travel
# with the Aurora resources.
resource "aws_iam_role_policy" "bedrock_rds_data" {
  name = "range-04-bedrock-rds-data-${var.scenario_id}"
  role = aws_iam_role.knowledge_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RdsDataApiAccess"
        Effect = "Allow"
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement"
        ]
        Resource = aws_rds_cluster.kb.arn
      },
      {
        # CreateKnowledgeBase validation calls the RDS control-plane
        # DescribeDBClusters API separately from the Data API above; without
        # this the knowledge base fails to create with an AccessDeniedException
        # on rds:DescribeDBClusters.
        Sid      = "RdsDescribeAccess"
        Effect   = "Allow"
        Action   = ["rds:DescribeDBClusters"]
        Resource = aws_rds_cluster.kb.arn
      },
      {
        Sid      = "RdsMasterSecretAccess"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_rds_cluster.kb.master_user_secret[0].secret_arn
      }
    ]
  })
}
