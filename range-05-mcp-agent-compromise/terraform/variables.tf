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
  description = "Azure OpenAI model deployed behind the agent. Must be a chat-completions model with native tool/function-calling support. gpt-4o-mini keeps the lab cheap; swap to gpt-4o if the walkthrough needs stronger tool-selection behavior."
  type        = string
  default     = "gpt-4o-mini"
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
  description = "CIDR(s) allowed to reach the storage account, Key Vault, AI Foundry account, and the MCP server Container App. Auto-detected to the operator's own public IP (/32) when left null - see access.tf. Set explicitly if you're applying from one network but walking the attack chain from another."
  type        = list(string)
  default     = null
}

variable "mcp_server_image" {
  description = "Container image reference for the MCP server (../mcp-server, built from its Dockerfile). Defaults to a placeholder image until you build and push the real one - see container_app.tf for the az acr build command to run after the initial apply."
  type        = string
  default     = null
}
