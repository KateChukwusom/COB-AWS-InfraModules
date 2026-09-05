output "db_instance_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "security_group_id" {
  value = aws_security_group.this.id
}

# ------------------------------------------------------------------
# Points to the AWS-managed secret RDS created automatically via
# manage_master_user_password. master_user_secret is a list because
# it's only populated when that feature is enabled - same [0]
# indexing pattern used for other conditionally-created attributes
# elsewhere in COB.
# ------------------------------------------------------------------
output "secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}