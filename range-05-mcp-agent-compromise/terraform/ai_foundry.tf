# =======================================================
# ATTACK CHAIN STEP 2 - THE AGENT (Azure AI Foundry / Azure OpenAI)
#
# Azure AI Foundry account configured for project management (the
# modern Foundry resource shape - NOT the legacy Hub/Workspace
# pattern that azurerm_ai_foundry / azurerm_ai_foundry_project model;
# see NOTES.md for why that older pair was rejected for this range),
# a Foundry project under it, and a tool/function-calling-capable
# Azure OpenAI chat model deployment. The over-scoped identity from
# identity.tf is attached here via `identity {}` - this account is
# the agent's compute from Terraform's point of view: Azure AI
# Foundry Agent Service is fully managed, so there is no VM,
# container, or App Service of our own to attach the identity to.
#
# Azure AI Content Safety / Prompt Shields is wired in as a custom
# RAI (Responsible AI) policy with its Jailbreak and Indirect Attack
# content filters turned on and set to block - this is the Prompt
# Shields capability, exposed through the azurerm provider as
# content_filter blocks on azurerm_cognitive_account_rai_policy
# (confirmed against the provider's current resource schema; see
# NOTES.md). The deployment references that policy via
# rai_policy_name, which is required for the guardrail test this
# range sets up for later - without it, the deployment falls back to
# the account's default content filter, which does not expose these
# categories as a policy you can point at.
#
# NOT COVERED HERE: the Agent object itself (its name, instructions,
# and tool/function JSON schema) and the actual MCP-style tool
# backend it calls. As of this writing there is no stable azurerm
# (or documented azapi) resource for
# Microsoft.CognitiveServices/accounts/projects/agents - Agent
# creation happens through the Azure AI Foundry Agents SDK or REST
# API against the project endpoint exported in outputs.tf, after this
# stack is applied. See NOTES.md for what was checked and the
# TODO below for exactly what's left.
# =======================================================

resource "azurerm_cognitive_account" "foundry" {
  name                = "aif-${local.name_prefix}-${local.suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  kind     = "AIServices"
  sku_name = "S0"

  # Required for Entra ID / managed-identity-dependent features,
  # including the Agent Service, and for project_management_enabled.
  custom_subdomain_name = "aif-${local.name_prefix}-${local.suffix}"

  # Enables the modern Foundry "project" child resource used below.
  project_management_enabled = true

  # THE OVER-SCOPED IDENTITY - attached here too, but currently UNUSED:
  # the orchestrator (orchestrator/agent_loop.py) calls this account's
  # plain chat-completions endpoint directly, which never touches a
  # managed identity. The identity is actually exercised at the Container
  # App (container_app.tf) that runs the MCP server's read_secret call -
  # see NOTES.md design decision #2. This attachment is kept only so a
  # future native Azure AI Foundry Agent Service integration (the TODO
  # below) has an identity already in place if/when it needs one; until
  # then, treat it as documented-but-dead wiring, not a second live path.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agent.id]
  }

  # Reachable, but only from local.allowed_source_cidrs (access.tf) - the
  # orchestrator (orchestrator/agent_loop.py) calls this account's chat-
  # completions endpoint directly from wherever the operator runs it, so
  # this is the actual "front door" worth restricting, same reasoning as
  # the storage account and the Container App ingress below.
  # TODO (yours to complete): go further still - a private endpoint +
  # VNet, matching the networking lockdown already done for ranges 1 & 2
  # - and re-verify the model deployment still works over the private
  # path before relying on it for a walkthrough.
  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    ip_rules       = local.firewall_ip_rules
  }

  tags = local.common_tags
}

resource "azurerm_cognitive_account_project" "support_agent" {
  name                 = "proj-${local.name_prefix}-${local.suffix}"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  location             = azurerm_cognitive_account.foundry.location
  display_name         = "MCP Agent Compromise - Support Agent"
  description          = "Internal support agent project - tool/function-calling enabled, backs the range-05 scenario."

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# -------------------------------------------------------
# CONTENT SAFETY / PROMPT SHIELDS
# Custom RAI policy with Jailbreak and Indirect Attack filtering - these
# two categories ARE Prompt Shields; the azurerm provider has no separate
# "Content Safety account" resource for this, it's a content_filter on
# the RAI policy attached to the deployment below. The provider's
# documentation says severity_threshold "does not apply" to Jailbreak/
# Indirect Attack. Under provider 4.81.0 the schema marked the argument
# required on every content_filter block regardless of filter type
# (confirmed by `terraform validate` at the time), so it was set to
# "Low" on both as a then-required-but-inert placeholder - that reading
# was wrong. Under the now-installed 5.11.0 schema the argument isn't
# just optional, it's actively rejected on these two filter names
# specifically (a live-apply CustomizeDiff check, not caught by
# `terraform validate`): "severity_threshold is not applicable for
# content_filter[0] with name Jailbreak" (and, if left in place here,
# the same for "Indirect Attack"). Omitted on both blocks below.
#
# block_enabled is driven by var.enable_prompt_shields (default true) so
# the SAME deployment can be re-applied with shields present-but-not-
# blocking for the guardrail on/off comparison the project spec asks for,
# without hand-editing this file between runs. The Indirect Attack filter
# is the one that matters here: TICKET-4017's injected instruction
# (mcp-server/mock_data.py) is a textbook indirect prompt injection, so
# with shields on (the default) the primary chained attack may be blocked
# before read_secret/notify ever run - that's the "on" half of the test,
# not a bug; re-apply with -var="enable_prompt_shields=false" to see the
# chain run unblocked, then re-apply with it back to true to see what's
# actually caught.
# -------------------------------------------------------
resource "azurerm_cognitive_account_rai_policy" "prompt_shields" {
  name                 = "range05-prompt-shields"
  cognitive_account_id = azurerm_cognitive_account.foundry.id
  base_policy_name     = "Microsoft.DefaultV2"
  mode                 = "Blocking"

  content_filter {
    name           = "Jailbreak"
    source         = "Prompt"
    filter_enabled = true
    block_enabled  = var.enable_prompt_shields
  }

  content_filter {
    name           = "Indirect Attack"
    source         = "Prompt"
    filter_enabled = true
    block_enabled  = var.enable_prompt_shields
  }

  tags = local.common_tags
}

# -------------------------------------------------------
# MODEL DEPLOYMENT - tool/function-calling enabled
# Tool/function calling is a capability of the chat-completions
# model itself (gpt-4o family), not a separate switch - it's
# enabled by presenting the model with a tool manifest at inference
# time, which is part of the Agent object (see the TODO below), not
# this deployment. What this resource controls is which model is
# deployed, its throughput, and - via rai_policy_name - the Prompt
# Shields policy above.
# -------------------------------------------------------
resource "azurerm_cognitive_deployment" "agent_model" {
  name                 = "range05-agent-model"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = var.openai_model_name
    version = var.openai_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = var.openai_deployment_capacity
  }

  rai_policy_name = azurerm_cognitive_account_rai_policy.prompt_shields.name

  depends_on = [azurerm_cognitive_account_project.support_agent]
}

# TODO (yours to complete): create the Agent object + its single
# tool/function definition (the FAQ-lookup tool described in
# identity.tf) via the Azure AI Foundry Agents SDK or REST API
# (POST {project endpoint}/assistants, api-version per the current
# Foundry Agents REST reference) against
# azurerm_cognitive_account_project.support_agent's endpoint, once
# this stack is applied. Give the agent ONLY the FAQ-lookup tool
# in its manifest - the point of this range is that the identity
# behind it is over-scoped regardless of how narrow the tool
# manifest is kept.
