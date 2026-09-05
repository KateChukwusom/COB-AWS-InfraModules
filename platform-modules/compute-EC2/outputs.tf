output "security_group_id" {
  value = aws_security_group.COB-sg.id
}

output "launch_template_id" {
  value = aws_launch_template.COB-launch_template.id
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.COB-asg.id
}