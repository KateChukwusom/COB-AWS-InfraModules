output "vpc_id" {
  value = module.networking.vpc_id
}

output "uploads_bucket" {
  value = module.storage.bucket_id
}

output "ec2_instance_id" {
  value = module.compute_ec2.instance_id
}