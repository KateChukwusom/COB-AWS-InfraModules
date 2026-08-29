
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

/*The essence of locals is to enforce COB's naming convention
The convention is baked in by the interpolation of team name and environment 
*/
locals {
  role_name = "COB-${var.team}-${var.environment}-role"

  tags = {
    Team        = var.team
    Environment = var.environment
    ManagedBy   = "COB"
  }

  actions_lookup = {
    s3 = {
      "read-only"  = ["s3:GetObject", "s3:ListBucket"]
      "read-write" = ["s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:DeleteObject"]
    }
    dynamodb = {
      "read-only"  = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"]
      "read-write" = ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"]
    }
    rds = {
      "read-only"  = ["rds:DescribeDBInstances", "rds:ListTagsForResource"]
      "read-write" = ["rds:DescribeDBInstances", "rds:ListTagsForResource", "rds:ModifyDBInstance"]
    }
    glue = {
      "read-only"  = ["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions"]
      "read-write" = ["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions", "glue:CreateTable", "glue:UpdateTable"]
    }
  }

#These represents the actions that the role ends up with
  granted_actions = local.actions_lookup[var.resource_service][var.access_level]

  # Boundary policies already exist, this module only looks them up, never
  # creates them, this map was generated in this module.
  boundary_policy_arn_map = {
    "read-only"  = data.aws_iam_policy.boundary_read_only.arn
    "read-write" = data.aws_iam_policy.boundary_read_write.arn
  }
}

# boundary permissions data sources
data "aws_iam_policy" "boundary_read_only" {
  name = "platform-boundary-read-only"
}

data "aws_iam_policy" "boundary_read_write" {
  name = "platform-boundary-read-write"
}

# trust policy: this policy document states who is trusted to assume the role
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [var.trusted_principal]
    }
  }
}

resource "aws_iam_role" "COB_iam_role" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = local.tags
  permissions_boundary = local.boundary_policy_arn_map[var.access_level]
}

# permission policy
data "aws_iam_policy_document" "permissions_policy" {
  statement {
    effect    = "Allow"
    actions   = local.granted_actions
    resources = var.resource_arns
  }
}

resource "aws_iam_role_policy" "COB_role_policy" {
  name   = "${local.role_name}-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_iam_instance_profile" "this" {
  count = var.create_instance_profile ? 1 : 0
  name = local.role_name
  role = aws_iam_role.this.name
  tags = local.tags
}