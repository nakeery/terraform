# variables.tf
variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

# variable "profile" {
#   description = "AWS profile to use"
#   type        = string
#   profile     = $env:AWS_PROFILE 
# }