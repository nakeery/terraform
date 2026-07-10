variable "region" {
  description = "AWS region to deploy the scenario"
  type        = string
  default     = "us-east-1"
}

variable "cgid" {
  description = "CloudGoat scenario instance ID - used to namespace resources"
  type        = string
  default     = "rag-injection"
}

variable "cg_whitelist" {
  description = "List of CIDR IPs allowed to interact with the scenario (applied as an aws:SourceIp condition on the attacker credentials)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bedrock_model_id" {
  description = "Bedrock model ID to use for the agent"
  type        = string
  default     = "anthropic.claude-3-sonnet-20240229-v1:0"
}
