# -------------------------------------------------------
# OPERATOR-IP ACCESS ALLOWLIST
#
# Mirrors range-04's access.tf (AWS aws:SourceIp condition fed by an
# auto-detected CIDR). This range's equivalent levers are Azure network
# ACLs: the storage account (storage.tf), the AI Foundry account
# (ai_foundry.tf), and the MCP server's Container App (container_app.tf)
# each restrict their data/management plane to local.allowed_source_cidrs
# instead of the open internet. Key Vault (keyvault.tf) is deliberately
# NOT part of this allowlist - see the comment there. Same
# checkip.amazonaws.com lookup used in range-04 - it's a plain "what's my
# public IP" endpoint, not AWS-specific.
# -------------------------------------------------------

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

locals {
  # Auto-detected /32 by default; var.allowed_source_cidrs overrides when set.
  allowed_source_cidrs = var.allowed_source_cidrs != null ? var.allowed_source_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]

  # The Storage and Cognitive Services firewalls (storage.tf, ai_foundry.tf)
  # reject /31 and /32 outright - their ip_rules schema only accepts a bare
  # IP address or a CIDR with a 0-30 prefix, so a single host has to be
  # passed with no prefix at all. The Container App's ingress IP
  # restriction (container_app.tf) is a different API (Microsoft.App, not
  # Microsoft.Storage/CognitiveServices) and accepts /32 fine, so it keeps
  # using allowed_source_cidrs directly.
  firewall_ip_rules = [for cidr in local.allowed_source_cidrs : trimsuffix(cidr, "/32")]
}
