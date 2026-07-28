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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # For a real portfolio project, consider using an S3 backend
  # so state isn't just sitting on your laptop. Left as local
  # for simplicity while learning - revisit once comfortable.
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "eks-portfolio/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.region
  # profile = $env:AWS_PROFILE 
  default_tags {
    tags = {
      Project     = "eks-portfolio"
      ManagedBy   = "terraform"
      Environment = "learning"
    }
  }
}

# The Kubernetes provider needs the EKS cluster's connection info.
# We pull this dynamically from the aws_eks_cluster data source
# once the cluster exists, rather than hardcoding it.
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
