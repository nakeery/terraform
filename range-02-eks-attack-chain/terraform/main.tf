terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # No S3 backend here either - same as range-01-eks-secure-baseline, local state is fine
  # for a range that gets stood up and torn down in a single session.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "eks-vuln-range"
      ManagedBy   = "terraform"
      Environment = "training"
      # Deliberate marker so this is unmistakable in the AWS console -
      # never let this tag be confused with real infrastructure.
      Purpose = "INTENTIONALLY-VULNERABLE-DO-NOT-USE-FOR-REAL-WORKLOADS"
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", aws_eks_cluster.main.name,
      "--region", var.region
    ]
  }
}

locals {
  cluster_name = "${var.project_name}-${var.environment}"
}
