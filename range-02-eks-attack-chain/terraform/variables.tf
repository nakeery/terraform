variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used across all resources"
  type        = string
  default     = "eks-vuln-range"
}

variable "environment" {
  description = "Environment name (used in tags and naming)"
  type        = string
  default     = "training"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
  # Different /16 than range-01-eks-secure-baseline's 10.0.0.0/16 on purpose - if you ever
  # peer or run both stacks near each other, overlapping CIDRs would be
  # its own headache. Keep them distinct.
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  #aws eks describe-cluster-versions --include-all --query "clusterVersions[?versionStatus=='STANDARD_SUPPORT'].{Version:clusterVersion,EndOfStandardSupport:endOfStandardSupportDate}" --output table
  default = "1.36"
  # No reason to backdate this one just to add "unsupported k8s version"
  # as an extra vuln - it dilutes the attack chain with noise that isn't
  # tied to a specific technique. Keep the misconfigs intentional and
  # named, not just "everything is old."
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
  # One node is enough to demonstrate the attack chain and keeps the
  # blast radius (and cost) minimal - this isn't testing HA.
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 1
}
