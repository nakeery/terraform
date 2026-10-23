# -------------------------------------------------------
# PROVIDERS + PROJECT-WIDE CONFIG
# range-05-mcp-agent-compromise
#
# Fifth entry in the "Offensive Cloud & AI Range" series. Where
# range-04 (bedrock-rag-injection) hijacks an AWS Bedrock assistant
# through a poisoned knowledge-base document, this range moves the
# same lesson onto Azure AI Foundry and a different trigger: an
# over-scoped identity sitting behind a tool/function-calling agent,
# reachable the moment that agent's tool-calling path is abused
# (prompt injection via a tool result, a compromised MCP-style
# tool backend, or a malicious tool argument an operator didn't
# validate). No knowledge base, no document store - the agent's
# OWN over-privileged identity is the vulnerability, not a poisoned
# corpus.
#
# OPEN ITEM RESOLVED DURING SCAFFOLDING (see NOTES.md for the full
# writeup): as of this writing, the azurerm provider has no stable
# resource for the Agent object itself (Microsoft.CognitiveServices/
# accounts/projects/agents) or for its tool/function manifest - only
# for the account, project, model deployment, and content-filter
# (RAI) policy that back it. Agent + tool-definition creation is a
# TODO left for the SDK/REST layer once this stack is applied.
# -------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }

  # No remote backend - same as the sibling ranges, local state is fine
  # for a lab that gets stood up and torn down in a single session.
}

provider "azurerm" {
  # azurerm 4.x defaults features.key_vault.purge_soft_delete_on_destroy
  # (and the sibling purge_soft_deleted_*_on_destroy flags) to true, which
  # is exactly what this lab wants: `terraform destroy` should actually
  # free the Key Vault name instead of leaving it soft-deleted and
  # blocking a clean re-apply in the same subscription. Left as an empty
  # block rather than restating the defaults.
  features {}
}

# Random suffix so globally-unique names (Key Vault, Storage Account,
# Cognitive Services custom subdomain) don't collide across repeated
# stand-up/tear-down cycles or across multiple subscriptions.
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_prefix = "range05"
  suffix      = random_id.suffix.hex

  # Deliberate marker so this is unmistakable in the Azure portal - never
  # let this tag be confused with real infrastructure. Every identity,
  # vault, storage account and AI Foundry resource below is intentionally
  # insecure. Mirrors the Purpose tag convention used by ranges 01-04,
  # shortened per this range's own spec.
  common_tags = {
    Project     = "range-05-mcp-agent-compromise"
    Environment = "training"
    ManagedBy   = "terraform"
    Purpose     = "INTENTIONALLY-VULNERABLE-MCP-AGENT-COMPROMISE"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}-${local.suffix}"
  location = var.location

  tags = local.common_tags
}
