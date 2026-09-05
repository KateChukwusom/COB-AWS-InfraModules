output "vpc_id" {
  value = module.networking.vpc_id
}

output "uploads_bucket" {
  value = module.uploads_bucket.bucket_id
}

output "web_app_asg_name" {
  value = module.web_app_server.autoscaling_group_name
}