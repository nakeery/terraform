# =======================================================
# ATTACK CHAIN STEP 1 - THE OVER-SCOPED AGENT IDENTITY
#
# THE VULNERABILITY: a single user-assigned managed identity,
# attached to the Azure AI Foundry account that hosts the agent (see
# ai_foundry.tf), holding far more than the agent's stated job
# requires:
#
#   Agent's stated job: answer employee support questions, using one
#   tool that reads a single FAQ blob from the "agent-tool-data"
#   container (storage.tf) to ground its answers. That is the whole
#   job. It never needs to write anything, and it never needs a
#   secret from Key Vault.
#
#   What this identity actually holds:
#     - Key Vault Secrets User on the ENTIRE vault (every secret,
#       not just a scoped one the tool was built to use - there
#       isn't one. The agent has no legitimate reason to resolve
#       ANY Key Vault secret, let alone the unrelated billing DB
#       connection string planted in keyvault.tf).
#     - Storage Blob Data Contributor - READ AND WRITE - at the
#       STORAGE ACCOUNT scope, not scoped down to the one container
#       (agent-tool-data) its tool actually reads. That one grant
#       also reaches the sibling "sensitive-customer-records"
#       container, and grants write/delete on both, when the tool
#       only ever needs to read one blob in one container.
#
# This is the same class of failure as range-04's over-privileged
# tool Lambda role: least-privilege was skipped at design time
# because "the agent might need it eventually," and the identity is
# attached broadly (account-level / storage-account-level) instead
# of to the one object the job actually touches. Once an attacker
# gets the agent to misuse its tool-calling path - a crafted tool
# argument, a compromised MCP-style tool backend, or a tool result
# that smuggles instructions back to the model - this identity is
# the blast radius. See NOTES.md for the full why-this-is-the-bug
# writeup.
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

# Storage read/write - scoped to the WHOLE STORAGE ACCOUNT. The
# tool only reads agent-tool-data/support_faq.txt. Correctly scoped,
# this would be "Storage Blob Data Reader" on the agent-tool-data
# CONTAINER alone - see agent_storage_read_scoped below for exactly
# that grant, added alongside this one as a documented before/after.
resource "azurerm_role_assignment" "agent_storage_readwrite" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}

# THE "FIXED" GRANT - Storage Blob Data Reader, scoped to the ONE
# container (agent-tool-data) the tool actually reads, nothing else.
# This is what the identity would hold if it had been scoped
# correctly from the start; it coexists with the over-scoped grant
# above on purpose, as a before/after - Azure RBAC is additive, so
# the identity's *effective* access is still the union of both until
# the over-scoped grant is removed.
#
# TODO (yours to complete): comment out (or destroy)
# agent_storage_readwrite above, re-apply, and re-run the walkthrough
# to show the tool still works with only this scoped grant in place -
# i.e. least privilege, demonstrated live, not just declared. Left as
# an exercise rather than done here because removing the over-scoped
# grant by default would remove the very over-privilege this range
# exists to teach. Blocked on a known gap until then: storage.tf's
# network rule doesn't yet let the Container App's own data-plane
# blob reads through (see NOTES.md, "Known gap") - fix that first or
# this scoped-down tool call will fail on the network layer before
# RBAC is ever the limiting factor.
resource "azurerm_role_assignment" "agent_storage_read_scoped" {
  # .id, not .resource_manager_id - the latter is deprecated in azurerm 4.x
  # (confirmed by `terraform validate`); .id is now the ARM resource ID for
  # this resource, not the old data-plane composite ID.
  scope                = azurerm_storage_container.tool_data.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}
