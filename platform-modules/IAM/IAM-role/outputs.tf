

output "role_arn" {
  description = "ARN of the created role, the identity other modules attach."
  value       = aws_iam_role.COB_iam_role.arn
}

output "role_name" {
  description = "Name of the created role, for debugging/logging references."
  value       = aws_iam_role.COB_iam_role.name
}

/* This is only needed when create instance profile is true
otherwise it is NULL */

output "instance_profile_name" {
  value = var.create_instance_profile ? aws_iam_instance_profile.COB_instance_profile.name : null
}