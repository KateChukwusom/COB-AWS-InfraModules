
# Composes four primitives: networking, iam-role, compute,
# plus secure-data-bucket for file uploads. 

module "networking" {
  source = "../../modules/networking"

  team        = var.team
  environment = var.environment
  az_count    = 2
}


# The web app's identity. Trusted only by EC2, granted only what
# it needs: write access to the uploads bucket, scoped by ARN once
# that bucket exists below.
module "web_app_role" {
  source = "../../modules/iam-role"

  team        = var.team
  environment = var.environment
  purpose     = "web-app"

  trusted_services        = ["ec2.amazonaws.com"]
  create_instance_profile = true

  inline_policies = {
    "uploads-bucket-write" = data.aws_iam_policy_document.uploads_access.json
  }
}

data "aws_iam_policy_document" "uploads_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${module.uploads_bucket.bucket_arn}/*"]
  }
}


# Where the app stores uploaded files. Standard sensitivity so no
# dedicated KMS key needed for this use case.
module "uploads_bucket" {
  source = "../../modules/secure-data-bucket"

  team        = var.team
  environment = var.environment
  purpose     = "uploads"
  description = "File uploads from the internal tools web app."
}

# The web app server. Port 443 open from anywhere - this is a
# public-facing web app. No SSH ingress at all - access for
# management is assumed to go through SSM Session Manager instead.

module "web_app_server" {
  source = "../../modules/compute"

  team        = var.team
  environment = var.environment
  purpose     = "web-app"

  vpc_id                 = module.networking.vpc_id
  subnet_ids             = module.networking.private_subnet_ids
  instance_profile_name  = module.web_app_role.instance_profile_name

  instance_type    = "t3.small"
  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  ingress_rules = [
    {
      description = "HTTPS from anywhere"
      port        = 443
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}