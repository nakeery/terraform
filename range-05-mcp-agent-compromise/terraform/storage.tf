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
  public_network_access_enabled = true

  network_rules {
    default_action = "Deny"
    ip_rules       = local.allowed_source_cidrs
    bypass         = ["AzureServices"]
  }

  # RBAC-only data plane - same reasoning as the Key Vault: the over-
  # scoped role assignment in identity.tf is the one grant that explains
  # the agent's reach into this account, with no shared key floating
  # around to muddy the attack chain.
  shared_access_key_enabled = true # TODO (yours to complete): flip to false and rework the seed upload below to use an RBAC-authenticated azurerm_storage_blob instead of an access key, then re-verify plan/apply.

  tags = local.common_tags
}

resource "azurerm_storage_container" "tool_data" {
  name                  = "agent-tool-data"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "sensitive_data" {
  name                  = "sensitive-customer-records"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# -------------------------------------------------------
# FAKE "SENSITIVE" DATASET
# Obviously-fake sample data - no real PII, no real credentials.
# Shaped like a customer export so the scenario reads realistically
# as a plausible exfiltration target.
# -------------------------------------------------------
resource "azurerm_storage_blob" "sensitive_sample" {
  name                   = "customer_export_sample.csv"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.sensitive_data.name
  type                   = "Block"
  source_content         = <<-EOT
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
  name                   = "support_faq.txt"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = azurerm_storage_container.tool_data.name
  type                   = "Block"
  source_content         = "Q: How do I reset my password?\nA: Visit the self-service portal and click 'Forgot password'.\n"
}
