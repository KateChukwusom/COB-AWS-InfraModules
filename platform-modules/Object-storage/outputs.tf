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
# Surfaced so iam-role's permission_policy_arns/inline_policies can
# scope grants (e.g. "GetObject only on THIS bucket") without the
# caller needing to reconstruct the ARN by hand.
# ------------------------------------------------------------------
output "kms_key_arn" {
  value = var.kms_key_arn
}