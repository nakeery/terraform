# =======================================================
# THE MCP SERVER'S COMPUTE
#
# Hosts the MCP server (../mcp-server) that owns read_secret - this is
# "the agent's compute" the over-scoped UAMI (identity.tf) is actually
# attached to for the live pivot: when read_secret calls Key Vault, it
# does so as this Container App's identity, not the operator's. Without
# this, the UAMI would sit attached to the Foundry account (ai_foundry.tf)
# with nothing ever running there to exercise it - documented over-
# privilege, but never a literally-exercised one. See NOTES.md for why a
# Container App was added here rather than treating the pivot as
# simulated.
#
# A Container Registry is included so there's somewhere real to push the
# built mcp-server image (see ../mcp-server/Dockerfile); this stack does
# NOT build or push that image itself - `terraform apply` provisions a
# placeholder-image Container App, then you run the az acr build command
# in this file's header comment to push the real image and the Container
# App picks it up on next revision.
# =======================================================

resource "azurerm_container_registry" "main" {
  name                = substr(lower(replace("acr${local.name_prefix}${local.suffix}", "-", "")), 0, 24)
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Basic"

  # Admin credentials, not a managed identity, for the Container App's
  # own image pull below - keeps "which identity can pull a benign lab
  # image" decoupled from the over-scoped UAMI this range is actually
  # about. Fine for a Basic-SKU registry holding nothing but this one
  # lab image.
  admin_enabled = true

  tags = local.common_tags
}

# After the first `terraform apply`, build and push the real mcp-server
# image, then re-apply (or just restart the revision) to pick it up:
#
#   az acr build --registry $(terraform output -raw mcp_server_registry_name) \
#     --image mcp-server:latest ../mcp-server
#
# Until then, var.mcp_server_image defaults to a public placeholder image
# so the stack applies cleanly on the first run.

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name_prefix}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${local.name_prefix}-${local.suffix}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = local.common_tags
}

resource "azurerm_container_app" "mcp_server" {
  name                         = "ca-${local.name_prefix}-mcp-${local.suffix}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  # THE OVER-SCOPED IDENTITY, attached to the compute that actually makes
  # the Key Vault call - see identity.tf for exactly what it can reach.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }

  registry {
    server               = azurerm_container_registry.main.login_server
    username             = azurerm_container_registry.main.admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = azurerm_container_registry.main.admin_password
  }

  template {
    # Pinned to exactly one replica, never scaled to zero: the ticket
    # store, secret cache, and comment thread the attack chain depends on
    # (mcp-server/mock_data.py) are in-memory, per-process globals. A
    # second replica or a scale-to-zero reset would break the exfil-loop
    # proof step (notify() writing a comment, then a later
    # get_ticket_status() call on a DIFFERENT replica not seeing it) -
    # this is a walkthrough-reliability fix, not a security control.
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "mcp-server"
      image  = coalesce(var.mcp_server_image, "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest")
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "MCP_TRANSPORT"
        value = "streamable-http"
      }
      env {
        name  = "PORT"
        value = "8000"
      }
      env {
        name  = "KEY_VAULT_URI"
        value = azurerm_key_vault.main.vault_uri
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.agent.client_id
      }
      # Matched to this app's own FQDN below so the MCP SDK's DNS-
      # rebinding protection accepts the Host header ingress presents.
      env {
        name  = "MCP_ALLOWED_HOST"
        value = "ca-${local.name_prefix}-mcp-${local.suffix}.${azurerm_container_app_environment.main.default_domain}"
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }

    # Reachable only from local.allowed_source_cidrs (access.tf) - same
    # orchestrator-calls-this-directly reasoning as the Foundry account's
    # network_acls in ai_foundry.tf. Any custom IP restriction rule set
    # makes every non-matching request an implicit deny.
    dynamic "ip_security_restriction" {
      for_each = local.allowed_source_cidrs
      content {
        name             = "allow-operator-${ip_security_restriction.key}"
        action           = "Allow"
        ip_address_range = ip_security_restriction.value
      }
    }
  }

  tags = local.common_tags
}
