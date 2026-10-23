# -------------------------------------------------------
# PIVOT TARGET - KEY VAULT
# Represents an internal secret that has nothing to do with the
# agent's stated job. In a real environment this might be a
# database connection string, an upstream API key, or a service
# credential shared across unrelated internal apps. The agent's
# over-scoped identity (identity.tf) can read EVERY secret in this
# vault, not just one scoped for its own use - that's the
# vulnerability this range demonstrates, not an oversight.
# -------------------------------------------------------

resource "azurerm_key_vault" "main" {
  name                = substr("kv-${local.name_prefix}-${local.suffix}", 0, 24)
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC authorization (not vault access policies) so the over-scoped
  # role assignment in identity.tf is the single, auditable grant that
  # explains how the agent's identity reaches this secret - no separate
  # access-policy list to reconcile against it.
  rbac_authorization_enabled = true

  # Lab-only: real environments should set this true and accept the
  # forced-wait on hard delete. Left false here purely so repeated
  # stand-up/tear-down cycles of this training range don't require a
  # 7-90 day wait between runs.
  purge_protection_enabled = false

  # Deliberately NOT locked to local.allowed_source_cidrs (access.tf),
  # unlike storage.tf and the Container App ingress. The operator never
  # calls this vault directly as part of the attack chain - only the MCP
  # server's read_secret tool does, from inside the Container App, over
  # that App's own outbound public IP, which isn't known at plan time and
  # isn't the operator's IP. Firewalling to the operator's /32 here would
  # block the exact call the whole range exists to demonstrate. The
  # intended control on this vault is identity (RBAC - see identity.tf),
  # not network, which is itself part of the finding: an attacker who
  # reaches the over-scoped identity doesn't need to be on an allowed
  # network to exploit it.
  tags = local.common_tags
}

# -------------------------------------------------------
# DUMMY SECRET
# Obvious placeholder value - never a real credential. Named and
# shaped like a plausible internal secret so the scenario reads
# realistically, but the string itself is unmistakably fake.
# -------------------------------------------------------
resource "azurerm_key_vault_secret" "dummy" {
  name         = "internal-billing-db-connection-string"
  value        = "DUMMY-NOT-A-REAL-SECRET"
  key_vault_id = azurerm_key_vault.main.id

  # The deploying principal needs Key Vault Secrets Officer (or
  # equivalent) to write this; RBAC propagation after enabling it on
  # the vault can lag a few seconds, which is why this range doesn't
  # also try to read the secret back synchronously in the same apply.
  depends_on = [azurerm_role_assignment.deployer_secrets_officer]

  tags = local.common_tags
}

# The Terraform principal applying this stack needs write access to
# create the dummy secret above, since the vault is RBAC-authorized
# and starts with zero role assignments. Scope this to the vault only.
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

data "azurerm_client_config" "current" {}
