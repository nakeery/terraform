# -------------------------------------------------------
# OPERATOR-IP ACCESS ALLOWLIST
#
# range-03 has no network endpoint (IAM + S3 only), so the applicable lever is an
# aws:SourceIp condition on the low-priv attacker's inline policies (see iam.tf).
# It restricts which source IP can use the leaked foothold credentials. The IP is
# auto-detected so there's no manual -var step.
#
# Scope limit: this gates only the low-priv user's DIRECT calls. Once the chain
# escalates (Step 2 mints admin_target's key, Step 3 runs the privileged_exec
# role via Lambda), those calls come from a different principal / an AWS-internal
# IP and are NOT bound by this condition - it locks the front door, not the whole
# chain.
# -------------------------------------------------------

# checkip.amazonaws.com returns the caller's public IPv4 as plaintext with a
# trailing newline (hence chomp() below).
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Optional override / fallback: set this to skip auto-detection (e.g. checkip is
# unreachable, or you need to allow additional CIDRs).
variable "allowed_source_cidrs" {
  description = "CIDRs allowed to use the low-priv attacker credentials; overrides the auto-detected IP when set"
  type        = list(string)
  default     = null
}

locals {
  # Auto-detected /32 by default; var.allowed_source_cidrs overrides when set.
  allowed_source_cidrs = var.allowed_source_cidrs != null ? var.allowed_source_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
}
