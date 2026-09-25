# -------------------------------------------------------
# PROVIDERS + PROJECT-WIDE CONFIG
# range-03-iam-privilege-escalation
#
# This is the identity-layer entry in the "Offensive Cloud &
# AI Range" series. Where range-01 (eks-secure-baseline) shows
# the controls done right and range-02 (eks-attack-chain) breaks
# the infrastructure layer, this range breaks the IAM layer: a
# low-privilege foothold that walks up to full account access
# through documented, named privilege-escalation techniques.
# -------------------------------------------------------
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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # No S3 backend here - same as the sibling ranges, local state is
  # fine for a lab that gets stood up and torn down in a single
  # session. Nothing here is meant to be long-lived.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "range-03-iam-privilege-escalation"
      ManagedBy   = "terraform"
      Environment = "training"
      # Deliberate marker so this is unmistakable in the AWS console -
      # never let this tag be confused with real infrastructure. Every
      # user, policy and bucket below is intentionally insecure.
      Purpose = "INTENTIONALLY-VULNERABLE-DO-NOT-USE-FOR-REAL-WORKLOADS"
    }
  }
}

# Random suffix so IAM user names and the (globally-unique) bucket
# name don't collide across repeated stand-up/tear-down cycles or
# across multiple accounts.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = var.project_name
}
