variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt the uploads bucket."
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the web app EC2 instance."
  type        = string
}