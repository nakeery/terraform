# -------------------------------------------------------
# PIVOT TARGET - STORAGE ACCOUNT
# Holds a fake "sensitive" dataset the agent's stated job never
# needs to touch, in a container separate from anything the agent's
# tool legitimately reads or writes. The over-scoped identity
# (identity.tf) gets Storage Blob Data Contributor - read AND write -
# at the STORAGE ACCOUNT scope, so it reaches this container too.
# A correctly-scoped identity would get Storage Blob Data Reader on
# this one container alone, if it needed this data at all.
# -------------------------------------------------------

resource "azurerm_storage_account" "main" {
  name                = substr(lower(replace("st${local.name_prefix}${local.suffix}", "-", "")), 0, 24)
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Reachable, but only from local.allowed_source_cidrs (access.tf) - not
  # the open internet. A real deployment handling anything sensitive would
  # go further still and front access entirely through managed identities
  # + Private Endpoints instead of a public endpoint with an IP allowlist.
  public_network_access = "Enabled"

  network_rules {
    default_action = "Deny"
    ip_rules       = local.firewall_ip_rules
    bypass         = ["AzureServices"]
  }

  # RBAC-only data plane - same reasoning as the Key Vault: the over-
  # scoped role assignment in identity.tf is the one grant that explains
  # the agent's reach into this account, with no shared key floating
  # around to muddy the attack chain. Requires provider.storage_use_azuread
  # (main.tf) and a data-plane RBAC grant for the deploying principal
  # (deployer_storage_blob_contributor below) so Terraform itself can still
  # create the seed containers/blobs without a key.
  shared_access_key_enabled = false

  tags = local.common_tags
}

# The Terraform principal applying this stack needs data-plane write
# access to create the seed containers/blobs below, now that the account
# has no access key - same propagation-lag reasoning as
# deployer_secrets_officer in keyvault.tf. Scoped to this account only,
# distinct from the agent's own (over- and correctly-scoped) grants in
# identity.tf.
resource "azurerm_role_assignment" "deployer_storage_blob_contributor" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# NOTE (checked against the provider's own docs, not assumed): the
# azurerm_storage_container docs state that *changing* container_access_type
# on an existing container always falls back to Shared Key, which this
# account no longer has. container_access_type = "private" is this
# resource's own default, so initial creation shouldn't trigger that code
# path - but if you ever need to change it on a container that already
# exists, temporarily set shared_access_key_enabled back to true first.
resource "azurerm_storage_container" "tool_data" {
  name                  = "agent-tool-data"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.deployer_storage_blob_contributor]
}

resource "azurerm_storage_container" "sensitive_data" {
  name                  = "sensitive-customer-records"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"

  depends_on = [azurerm_role_assignment.deployer_storage_blob_contributor]
}

# -------------------------------------------------------
# FAKE "SENSITIVE" DATASET
# Obviously-fake sample data - no real PII, no real credentials.
# Shaped like a customer export so the scenario reads realistically
# as a plausible exfiltration target.
# -------------------------------------------------------
resource "azurerm_storage_blob" "sensitive_sample" {
  name                 = "customer_export_sample.csv"
  storage_container_id = azurerm_storage_container.sensitive_data.id
  type                 = "Block"
  source_content       = <<-EOT
    customer_id,full_name,email,fake_ssn,notes
    1001,Jane Fakeperson,jane.fakeperson@example.invalid,000-00-0001,SAMPLE DATA - NOT REAL
    1002,John Q. Example,john.example@example.invalid,000-00-0002,SAMPLE DATA - NOT REAL
    1003,Pat Placeholder,pat.placeholder@example.invalid,000-00-0003,SAMPLE DATA - NOT REAL
  EOT

  # azurerm_storage_blob does not support a `tags` argument (blob-level
  # index tags are a different, data-plane concept the resource
  # doesn't expose) - tagging stops at the storage account.
}

# Benign seed data in the container the agent's tool is actually
# meant to use - gives the tool-calling path something real to
# retrieve during a walkthrough before any pivot happens.
resource "azurerm_storage_blob" "tool_seed" {
  name                 = "support_faq.txt"
  storage_container_id = azurerm_storage_container.tool_data.id
  type                 = "Block"
  source_content       = "Q: How do I reset my password?\nA: Visit the self-service portal and click 'Forgot password'.\n"
}
