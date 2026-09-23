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

# aws bedrock list-inference-profiles --region us-east-1 --type-equals SYSTEM_DEFINED --query "inferenceProfileSummaries[].inferenceProfileId" --output json
variable "bedrock_model_id" {
  description = "Bedrock model (cross-region inference profile) ID the AgentCore harness runs the assistant on. Defaults to Amazon Nova Micro v1 - cheap and capable enough for this lab's tool-use flow. "
  type        = string
  default     = "us.amazon.nova-micro-v1:0"
}
