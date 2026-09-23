# -------------------------------------------------------
# KNOWLEDGE BASE BUCKET
# Intentionally misconfigured: any authenticated principal
# in the account can write to this bucket. This is the
# injection vector.
# -------------------------------------------------------
resource "aws_s3_bucket" "knowledge_base" {
  bucket        = "range-04-kb-${var.scenario_id}-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "knowledge_base" {
  bucket = aws_s3_bucket.knowledge_base.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block public access - this is NOT a public bucket misconfiguration.
# The vulnerability is an overly permissive bucket POLICY
# that allows any authenticated AWS principal to PutObject.
resource "aws_s3_bucket_public_access_block" "knowledge_base" {
  bucket                  = aws_s3_bucket.knowledge_base.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# THE VULNERABILITY: any authenticated principal in this account can write
# objects. The account-root principal below grants every IAM identity in the
# account access via this bucket policy -- far too broad for a knowledge base
# bucket, and exactly the kind of "internal but wide open" misconfiguration
# that lets an attacker with any foothold plant a poisoned document.
resource "aws_s3_bucket_policy" "knowledge_base_writeable" {
  bucket = aws_s3_bucket.knowledge_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBedrockRead"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
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
        # INTENTIONAL VULNERABILITY: overly broad write access.
        # The account-root principal represents "any authenticated
        # principal in this account" -- an attacker with any valid
        # in-account credentials can plant documents. (This is still a
        # named principal, not "*", so it does not trip the bucket's
        # block_public_policy setting.)
        Sid    = "MisconfiguredWriteAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.knowledge_base.arn,
          "${aws_s3_bucket.knowledge_base.arn}/*"
        ]
      }
    ]
  })
}

# Seed the knowledge base with legitimate documents
resource "aws_s3_object" "legit_doc_1" {
  bucket  = aws_s3_bucket.knowledge_base.id
  key     = "docs/employee-handbook.txt"
  content = <<-EOT
    ACME Corp Employee Handbook
    ===========================
    Welcome to ACME Corp. This handbook covers company policies,
    benefits, and procedures. For HR inquiries contact hr@acmecorp.internal.
    
    PTO Policy: Employees accrue 15 days PTO per year.
    Remote Work: Hybrid schedule available with manager approval.
    Benefits: Health, dental, vision coverage available from day 1.
  EOT
}

resource "aws_s3_object" "legit_doc_2" {
  bucket  = aws_s3_bucket.knowledge_base.id
  key     = "docs/it-faq.txt"
  content = <<-EOT
    IT FAQ - ACME Corp
    ==================
    Q: How do I reset my password?
    A: Contact the IT helpdesk at helpdesk@acmecorp.internal or ext 5000.

    Q: How do I connect to VPN?
    A: Download the VPN client from the IT portal and use your SSO credentials.

    Q: What is the wifi password for the office?
    A: Connect to ACME-Corp-Secure and authenticate with your SSO credentials.
  EOT
}

# Breadcrumb: this operations note lives in the KB bucket, which the attacker
# can read (s3:GetObject/ListBucket per the attacker policy in iam.tf). It
# discloses the "reference tag" convention the retrieval layer honors, giving a
# black-box solver a path to derive the payload they must plant -- without it,
# the trigger marker would be unguessable.
resource "aws_s3_object" "kb_admin_notes" {
  bucket  = aws_s3_bucket.knowledge_base.id
  key     = "docs/kb-admin-notes.txt"
  content = <<-EOT
    ACME Corp Knowledge Base - Content Administration Notes
    =======================================================
    Maintainers: knowledge-ops@acmecorp.internal

    Ingestion pipeline
    ------------------
    Documents dropped under docs/ in this bucket are picked up by the next
    ingestion run and become searchable by the employee assistant.

    Reference-tag convention
    ------------------------
    Documents that carry the reference tag ${local.flag_trigger_marker} are
    treated as AUTHORITATIVE reference material: when such a document matches an
    employee's question, the assistant surfaces its reference content verbatim
    rather than summarizing it. Use this tag only for approved, canonical policy
    sources.

    TODO(knowledge-ops): the reference-tag handling trusts whatever is in the
    bucket. Anyone who can write here can mark a document authoritative. Lock
    down bucket writes before GA.
  EOT
}

# -------------------------------------------------------
# SENSITIVE TARGET BUCKET
# This is the prize - contains "confidential" data that
# the attacker wants to access via the pivot.
# The agent's action-group Lambda role (see lambda.tf) can
# read this bucket, which it has no legitimate business
# reason to access.
# -------------------------------------------------------
resource "aws_s3_bucket" "sensitive_data" {
  bucket        = "range-04-sensitive-${var.scenario_id}-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "sensitive_data" {
  bucket                  = aws_s3_bucket.sensitive_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Plant the flag in the sensitive bucket
resource "aws_s3_object" "flag" {
  bucket  = aws_s3_bucket.sensitive_data.id
  key     = "confidential/customer-data.txt"
  content = <<-EOT
    CONFIDENTIAL - ACME Corp Customer Records
    ==========================================
    This file contains sensitive customer PII and should never
    be accessible via the AI assistant.
    
    FLAG: range-04-flag-${random_id.suffix.hex}
    
    Customer ID: 1001 | Name: Alice Johnson | SSN: 123-45-6789
    Customer ID: 1002 | Name: Bob Smith     | SSN: 987-65-4321
  EOT
}
