# -------------------------------------------------------
# OPERATOR-IP ACCESS ALLOWLIST
#
# range-02 has two internet-facing surfaces: the EKS API server public endpoint
# (eks.tf) and the vulnerable dashboard's LoadBalancer (k8s.tf). Both are locked
# to the operator's current public IP so this intentionally-vulnerable range is
# not exposed to the whole internet while it's up. The IP is auto-detected, so
# there's no manual -var step for the common case.
# -------------------------------------------------------

# checkip.amazonaws.com returns the caller's public IPv4 as plaintext with a
# trailing newline (hence chomp() below).
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

# Optional override / fallback: set this to skip auto-detection (e.g. checkip is
# unreachable, or you need to allow additional CIDRs). Mirrors range-04's name.
variable "allowed_source_cidrs" {
  description = "CIDRs allowed to reach range-02's public surfaces; overrides the auto-detected IP when set"
  type        = list(string)
  default     = null
}

locals {
  # Auto-detected /32 by default; var.allowed_source_cidrs overrides when set.
  allowed_source_cidrs = var.allowed_source_cidrs != null ? var.allowed_source_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
}
