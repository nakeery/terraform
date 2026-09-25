terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Scenario    = "range-04-bedrock-rag-injection"
      Environment = "training"
      ManagedBy   = "terraform"
      # Deliberate marker so this is unmistakable in the AWS console -
      # never let this tag be confused with real infrastructure. Every
      # bucket, role, Lambda and agent below is intentionally insecure.
      Purpose = "INTENTIONALLY-VULNERABLE-DO-NOT-USE-FOR-REAL-WORKLOADS"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Retrieval-side flag trigger marker. A planted KB document must contain this
  # string; when such a document is retrieved, kb_retrieval surfaces the flag.
  # Defined once here and referenced by both the retrieval Lambda's env var and
  # the discoverable breadcrumb document (s3.tf) so the two never drift.
  flag_trigger_marker = "ACME-KB-CANARY-2024"

  # The single flag value. Deliberately neutral -- no "secret"/"sk-"/"restricted"
  # wording -- so the model reads it as a mundane, quotable reference code and
  # doesn't refuse to relay it. Referenced by the retrieval Lambda (lambda.tf)
  # and the pivot-path flag object (s3.tf) so both stay the one value.
  flag_value = "range-04-flag-${random_id.suffix.hex}"
}
