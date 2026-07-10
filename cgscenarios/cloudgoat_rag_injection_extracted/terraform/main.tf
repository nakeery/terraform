terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "~> 2.2"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Scenario    = "cloudgoat-ai-rag-injection"
      Environment = "cloudgoat"
      ManagedBy   = "terraform"
    }
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}
