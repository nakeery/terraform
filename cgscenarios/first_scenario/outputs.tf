# outputs.tf
output "attacker_access_key_id" {
  value = aws_iam_access_key.cg_low_priv_key.id
}

output "attacker_secret_access_key" {
  value     = aws_iam_access_key.cg_low_priv_key.secret
  sensitive = true
}

output "loot_bucket" {
  value = aws_s3_bucket.loot.id
}