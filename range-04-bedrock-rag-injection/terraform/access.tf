# -------------------------------------------------------
# OPERATOR-IP ACCESS ALLOWLIST
#
# range-04 has no self-managed network endpoint to lock down (the AgentCore
# harness/gateway are AWS-managed SigV4 endpoints). The applicable lever is the
# aws:SourceIp condition on the attacker's IAM policy (see iam.tf), fed by the
# allowed_source_cidrs variable (variables.tf). This file auto-detects the
# operator's public IP so that condition defaults to the operator's own IP
# instead of 0.0.0.0/0 - no manual -var step for the common case.
# -------------------------------------------------------

# checkip.amazonaws.com returns the caller's public IPv4 as plaintext with a
# trailing newline (hence chomp() below).
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com/"
}

locals {
  # Auto-detected /32 by default; var.allowed_source_cidrs overrides when set.
  allowed_source_cidrs = var.allowed_source_cidrs != null ? var.allowed_source_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
}
