output "bucket_id" {
  value = aws_s3_bucket.COB_s3_bucket.id
}

output "bucket_arn" {
  value = aws_s3_bucket.COB_s3_bucket.arn
}

output "bucket_domain_name" {
  value = aws_s3_bucket.COB_s3_bucket.bucket_domain_name
}

output "kms_key_arn" {
  value = local.kms_key_arn
}