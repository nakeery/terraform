# -------------------------------------------------------
# SECRETS MANAGER SECRET
# Represents an internal API key or credential that
# the Bedrock agent's overprivileged role can access.
# In a real environment this might be a database password,
# an internal API key, or a service account credential.
# -------------------------------------------------------
resource "aws_secretsmanager_secret" "internal_api_key" {
  name                    = "range-04-internal-api-key-${var.scenario_id}-${random_id.suffix.hex}"
  description             = "ACME Corp internal API key - should never be accessible via AI assistant"
  recovery_window_in_days = 0 # Allow immediate deletion on destroy
}

resource "aws_secretsmanager_secret_version" "internal_api_key" {
  secret_id = aws_secretsmanager_secret.internal_api_key.id

  secret_string = jsonencode({
    api_key     = "sk-acme-internal-${random_id.suffix.hex}"
    description = "Internal service API key for ACME Corp backend systems"
    note        = "FLAG: range-04-secret-flag-${random_id.suffix.hex}"
  })
}
