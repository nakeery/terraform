# -------------------------------------------------------
# THE LOOT
# A secret that only a fully-privileged principal should be able
# to read. The whole point of the attack chain in iam.tf is to
# escalate from the low-priv foothold to something that CAN read
# this object. It is the "flag" the walkthrough collects at the end.
# -------------------------------------------------------
resource "aws_s3_bucket" "loot" {
  bucket        = "${local.name_prefix}-loot-${random_id.suffix.hex}"
  force_destroy = true
}

# The loot bucket is private by default (AWS Block Public Access is on by default
# for new buckets). This pins that shut explicitly so the range's exposure is
# unmistakably IAM-only - the escalation is the vulnerability, not a public
# bucket. Not an IP restriction; access is still gated purely by IAM identity.
resource "aws_s3_bucket_public_access_block" "loot" {
  bucket                  = aws_s3_bucket.loot.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "secret" {
  bucket  = aws_s3_bucket.loot.id
  key     = "loot.txt"
  content = "You escalated successfully. Flag: {privesc_complete}"
}
