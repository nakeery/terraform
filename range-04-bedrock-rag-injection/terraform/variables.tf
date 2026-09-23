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
  description = "Bedrock model (cross-region inference profile) ID the AgentCore harness runs the assistant on. Defaults to Claude Haiku 4.5 - cheap and capable enough for this lab's tool-use flow. Like Claude Sonnet 4.5, Haiku 4.5 supports only INFERENCE_PROFILE invocation (no on-demand bare model ID), so this must be an inference profile ID (the \"us.\" prefix); it routes across us-east-1/us-east-2/us-west-2. AWS auto-enables model access for these models, so no manual opt-in is required. Swap in a Sonnet profile if you want more reliable injection on the first attempt."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
