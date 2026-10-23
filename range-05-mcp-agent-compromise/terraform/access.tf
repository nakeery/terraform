# -------------------------------------------------------
# OPERATOR-IP ACCESS ALLOWLIST
#
# Mirrors range-04's access.tf (AWS aws:SourceIp condition fed by an
# auto-detected CIDR). This range's equivalent levers are Azure network
# ACLs: the storage account (storage.tf), Key Vault (keyvault.tf), AI
# Foundry account (ai_foundry.tf), and the MCP server's Container App
# (container_app.tf) each restrict their data/management plane to
# local.allowed_source_cidrs instead of the open internet. Same
# checkip.amazonaws.com lookup used in range-04 - it's a plain "what's my
# public IP" endpoint, not AWS-specific.
# -------------------------------------------------------

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

locals {
  # Auto-detected /32 by default; var.allowed_source_cidrs overrides when set.
  allowed_source_cidrs = var.allowed_source_cidrs != null ? var.allowed_source_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
}
