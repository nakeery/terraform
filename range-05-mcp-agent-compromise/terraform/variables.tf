variable "location" {
  description = "Azure region to deploy the scenario. Azure AI Foundry's Agent Service, model tool/function-calling, and the content-filter (RAI) policies used here are not available in every region - eastus2 is a safe default with broad Agent Service + Content Safety coverage as of this writing. Re-check regional availability before changing this."
  type        = string
  default     = "eastus2"
}

variable "scenario_id" {
  description = "Scenario instance ID - used to namespace resources"
  type        = string
  default     = "mcp-agent"
}

variable "openai_model_name" {
  description = "Azure OpenAI model deployed behind the agent. Must be a chat-completions model with native tool/function-calling support. gpt-5-mini keeps the lab cheap and is confirmed to have nonzero GlobalStandard quota as of this writing (see terraform/NOTES.md) - gpt-4o-mini has no non-deprecating version left to deploy, and gpt-4o's GlobalStandard quota was 0 in the subscription this was checked against. Re-check `az cognitiveservices usage list` before assuming this still holds in yours."
  type        = string
  default     = "gpt-5-mini"
}

variable "openai_model_version" {
  description = "Model version to pin for openai_model_name. Left unset (null) to take the current default version at deploy time - check `az cognitiveservices account list-models` for valid values if you pin one, since availability varies by region and quota."
  type        = string
  default     = null
}

variable "openai_deployment_capacity" {
  description = "Deployment capacity in units of 1,000 Tokens-Per-Minute (TPM) for the GlobalStandard SKU. Kept small - this is a training range, not a production workload."
  type        = number
  default     = 10
}

variable "allowed_source_cidrs" {
  description = "CIDR(s) allowed to reach the AI Foundry account and the MCP server Container App - deliberately NOT Key Vault, see keyvault.tf. Auto-detected to the operator's own public IP (/32) when left null - see access.tf. Set explicitly if you're applying from one network but walking the attack chain from another."
  type        = list(string)
  default     = null
}

variable "mcp_server_image" {
  description = "Container image reference for the MCP server (../mcp-server, built from its Dockerfile). Defaults to a placeholder image until you build and push the real one - see container_app.tf for the az acr build command to run after the initial apply."
  type        = string
  default     = null
}

variable "enable_prompt_shields" {
  description = "Whether the Jailbreak + Indirect Attack (Prompt Shields) content filters actually block. true (default) is the realistic posture for a baseline comparison; set to false with -var to stand up the SAME deployment with shields present but not blocking, for the guardrail on/off test the project spec asks for - re-apply between runs rather than editing this file. Either way the RAI policy and both filters stay attached; only block_enabled toggles, so the deployment name/identity/network config never changes between runs."
  type        = bool
  default     = true
}
