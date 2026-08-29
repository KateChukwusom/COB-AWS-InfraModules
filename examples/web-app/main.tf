# main.tf
# Example consumer: a simple web app environment.
# Composes three COB capabilities: Networking, Storage, Compute-EC2.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "../../modules/networking"

  environment = var.environment
  vpc_cidr    = "10.20.0.0/16"
}

module "storage" {
  source = "../../modules/storage"

  bucket_name = "${var.environment}-webapp-uploads"
  environment = var.environment
  kms_key_arn = var.kms_key_arn
}

module "compute_ec2" {
  source = "../../modules/compute-ec2"

  environment = var.environment
  ami_id      = var.ami_id

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.public_subnet_ids
}