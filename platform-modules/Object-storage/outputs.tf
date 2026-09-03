output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  value = aws_s3_bucket.this.bucket_domain_name
}

# ------------------------------------------------------------------
# Points at the key this module created (or null, for standard-
# sensitivity buckets using AWS-managed encryption). Downstream
# iam-role policies use this to grant kms:Decrypt where a customer-
# managed key is actually in play.
# ------------------------------------------------------------------
output "kms_key_arn" {
  value = local.kms_key_arn
}