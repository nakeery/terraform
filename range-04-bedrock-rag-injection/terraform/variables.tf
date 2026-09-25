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
  description = "CIDRs allowed to use the attacker credentials (aws:SourceIp condition on the attacker policy). Defaults to the operator's auto-detected IP (see access.tf); set this to override, e.g. to add CIDRs or if checkip is unreachable."
  type        = list(string)
  default     = null
}

# aws bedrock list-inference-profiles --region us-east-1 --type-equals SYSTEM_DEFINED --query "inferenceProfileSummaries[].inferenceProfileId" --output json
variable "bedrock_model_id" {
  description = "Bedrock model (cross-region inference profile) ID the AgentCore harness runs the assistant on. Defaults to Amazon Nova Micro v1 - cheap and capable enough for this lab's tool-use flow. "
  type        = string
  default     = "us.amazon.nova-micro-v1:0"
}
