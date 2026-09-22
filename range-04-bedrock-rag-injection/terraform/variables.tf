variable "region" {
  description = "AWS region to deploy the scenario"
  type        = string
  default     = "us-east-1"
}

variable "scenario_id" {
  description = "Scenario instance ID - used to namespace resources"
  type        = string
  default     = "rag-injection"
}

variable "allowed_source_cidrs" {
  description = "List of CIDR IPs allowed to interact with the scenario (applied as an aws:SourceIp condition on the attacker credentials)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bedrock_model_id" {
  description = "Bedrock model (cross-region inference profile) ID to use for the agent. Claude Sonnet 4.5 and later don't support on-demand invocation by bare model ID - this must be an inference profile ID (the \"us.\" prefix), which also requires model access enabled in every region the profile can route to, not just var.region."
  type        = string
  default     = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
}
