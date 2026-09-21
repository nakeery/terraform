# outputs.tf
output "attacker_access_key_id" {
  description = "Access key ID for the low-privilege foothold user. Start the walkthrough with this."
  value       = aws_iam_access_key.low_priv.id
}

output "attacker_secret_access_key" {
  description = "Secret access key for the low-privilege foothold user. Pair with attacker_access_key_id to configure the AWS CLI."
  value       = aws_iam_access_key.low_priv.secret
  sensitive   = true
}

output "admin_target_user_name" {
  description = "The higher-privileged victim user. STEP 2 mints an access key for this user - it has no key of its own by design."
  value       = aws_iam_user.admin_target.name
}

output "loot_bucket" {
  description = "S3 bucket holding the secret only a fully-privileged principal should read - the flag the chain is trying to reach."
  value       = aws_s3_bucket.loot.id
}

output "warning" {
  description = "Read this before you forget you built this"
  value       = "This account contains intentionally over-privileged IAM users. Do not deploy it in a shared account, and do not reuse any user, policy or key here for a real workload. Destroy it the same session you stood it up."
}
