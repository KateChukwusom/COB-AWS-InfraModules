

output "role_arn" {
  description = "ARN of the created role, the identity other modules attach."
  value       = aws_iam_role.COB_iam_role.arn
}

output "role_name" {
  description = "Name of the created role, for debugging/logging references."
  value       = aws_iam_role.COB_iam_role.name
}