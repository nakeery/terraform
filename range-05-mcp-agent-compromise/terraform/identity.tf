# =======================================================
# ATTACK CHAIN STEP 1 - THE OVER-SCOPED AGENT IDENTITY
#
# THE VULNERABILITY: a single user-assigned managed identity,
# attached to the Azure AI Foundry account that hosts the agent (see
# ai_foundry.tf), holding far more than the agent's stated job
# requires:
#
#   Agent's stated job: look up ticket status for support requesters.
#   That is the whole job. It never needs to write anything outside a
#   ticket, and it never needs a secret from Key Vault.
#
#   What this identity actually holds:
#     - Key Vault Secrets User on the ENTIRE vault (every secret,
#       not just a scoped one the tool was built to use - there
#       isn't one. The agent has no legitimate reason to resolve
#       ANY Key Vault secret, let alone the unrelated billing DB
#       connection string planted in keyvault.tf).
#
# This is the same class of failure as range-04's over-privileged
# tool Lambda role: least-privilege was skipped at design time
# because "the agent might need it eventually," and the identity is
# attached broadly (vault-level) instead of to the one object - or
# zero objects - the job actually touches. Once an attacker gets the
# agent to misuse its tool-calling path - a crafted tool argument, a
# compromised MCP-style tool backend, or a tool result that smuggles
# instructions back to the model - this identity is the blast radius.
# See NOTES.md for the full why-this-is-the-bug writeup.
# =======================================================

resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-${local.name_prefix}-agent-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = local.common_tags
}

# Key Vault read - scoped to the WHOLE VAULT. A correctly-scoped
# design wouldn't grant this at all, since the agent's tool never
# touches Key Vault; if some future tool genuinely needed one
# secret, the fix is a per-secret RBAC scope
# (azurerm_key_vault_secret.dummy.resource_versionless_id), not the
# vault.
resource "azurerm_role_assignment" "agent_keyvault_read" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}
