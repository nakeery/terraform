# main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.74.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }

  }
}

provider "aws" {
  region  = var.region
}

# Random suffix so bucket names don't collide globally
resource "random_id" "suffix" {
  byte_length = 4
}

# --- The "loot": a secret only admins should read ---
resource "aws_s3_bucket" "loot" {
  bucket        = "cloudgoat-loot-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_object" "secret" {
  bucket  = aws_s3_bucket.loot.id
  key     = "cg_secret.txt"
  content = "You escalated successfully. Flag: {privesc_complete}"
}

# --- The low-privileged starting user ---
resource "aws_iam_user" "low_priv" {
  name          = "cg-low-priv-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_iam_user_policy_attachment" "cg_base_permissions"{
  user       = aws_iam_user.low_priv.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}


resource "aws_iam_access_key" "cg_low_priv_key" {
  user = aws_iam_user.low_priv.name
}

# --- The misconfiguration: user can attach ANY policy to itself ---
resource "aws_iam_user_policy" "cg_vulnerable" {
  name = "attach-policy-permission"
  user = aws_iam_user.low_priv.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:AttachUserPolicy", "iam:ListPolicies"]
        Resource = "*"
      }
    ]
  })
}