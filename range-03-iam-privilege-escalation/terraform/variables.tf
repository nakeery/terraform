# variables.tf
variable "region" {
  description = "AWS region to deploy into. Everything here is IAM + S3, so the region only matters for the S3 bucket and the CLI endpoints."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix applied to every IAM user, policy and bucket in this range. Kept short so resource names stay readable in the console alongside the random suffix."
  type        = string
  default     = "range-03-iam-privesc"
}
