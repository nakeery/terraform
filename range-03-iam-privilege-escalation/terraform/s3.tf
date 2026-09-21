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

resource "aws_s3_object" "secret" {
  bucket  = aws_s3_bucket.loot.id
  key     = "loot.txt"
  content = "You escalated successfully. Flag: {privesc_complete}"
}
