output "resource_group_name" {
  description = "Resource group holding every resource in this scenario"
  value       = azurerm_resource_group.main.name
}

output "agent_identity_client_id" {
  description = "Client ID of the over-scoped user-assigned managed identity attached to the agent's compute"
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "agent_identity_principal_id" {
  description = "Principal (object) ID of the over-scoped identity - the value every role assignment in identity.tf is granted to"
  value       = azurerm_user_assigned_identity.agent.principal_id
}

output "ai_foundry_account_endpoint" {
  description = "Azure AI Foundry account endpoint"
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "ai_foundry_project_endpoints" {
  description = "Endpoint map for the Foundry project - use this to create the Agent object via the SDK/REST (see the TODO in ai_foundry.tf)"
  value       = azurerm_cognitive_account_project.support_agent.endpoints
}

output "model_deployment_name" {
  description = "Name of the tool/function-calling-capable model deployment the agent should be configured to use"
  value       = azurerm_cognitive_deployment.agent_model.name
}

output "prompt_shields_policy_name" {
  description = "RAI policy name carrying the Jailbreak + Indirect Attack (Prompt Shields) content filters"
  value       = azurerm_cognitive_account_rai_policy.prompt_shields.name
}

output "key_vault_name" {
  description = "Name of the Key Vault holding the dummy secret (pivot target)"
  value       = azurerm_key_vault.main.name
}

output "storage_account_name" {
  description = "Name of the storage account holding the agent's legitimate tool data and the fake sensitive dataset (pivot target)"
  value       = azurerm_storage_account.main.name
}

output "sensitive_container_name" {
  description = "Container holding the fake sensitive dataset the agent's identity can reach but its stated job never needs"
  value       = azurerm_storage_container.sensitive_data.name
}

output "mcp_server_registry_name" {
  description = "Container Registry to push the real mcp-server image to (az acr build --registry <this> --image mcp-server:latest ../mcp-server), then re-apply/restart the Container App revision"
  value       = azurerm_container_registry.main.name
}

output "mcp_server_url" {
  description = "Public (CIDR-restricted) streamable-http endpoint for the MCP server Container App - point the orchestrator at this"
  value       = "https://${azurerm_container_app.mcp_server.ingress[0].fqdn}/mcp"
}

output "allowed_source_cidrs" {
  description = "CIDR(s) the storage account, AI Foundry account, and MCP server Container App are restricted to (auto-detected operator IP unless overridden)"
  value       = local.allowed_source_cidrs
}

output "warning" {
  description = "Reminder that everything in this scenario is intentionally insecure"
  value       = "INTENTIONALLY VULNERABLE. This stack builds an over-scoped, tool-calling Azure AI Foundry agent for training only. Deploy it in an isolated sandbox subscription, walk the chain, then 'terraform destroy'. Never point real workloads, real secrets, or real customer data at it."
}
