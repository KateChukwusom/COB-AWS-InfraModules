locals {
  name = "cob-${var.team}-${var.environment}-${var.purpose}"

  tags = merge(var.tags, {
    Team        = var.team
    Environment = var.environment
    ManagedBy   = "COB"
  })
}

# ------------------------------------------------------------------
# The logical container Glue and Athena both reference. Doesn't hold
# data itself - just metadata about tables discovered in the source
# bucket.
# ------------------------------------------------------------------
resource "aws_glue_catalog_database" "this" {
  name = replace(local.name, "-", "_")  # Glue database names don't allow hyphens
}

# ------------------------------------------------------------------
# The crawler's IAM role is composed from iam-role, not built here
# directly - reusing the same primitive rather than duplicating role-
# creation logic. Scoped narrowly: read-only on the source bucket
# specifically, plus decrypt on its KMS key only if one exists, plus
# AWS's own managed policy covering the Glue service's own baseline
# operational needs (writing crawler logs, updating the catalog).
# ------------------------------------------------------------------
data "aws_iam_policy_document" "crawler_s3_access" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]

    resources = [
      var.source_bucket_arn,
      "${var.source_bucket_arn}/${var.source_prefix}*"
    ]
  }

  dynamic "statement" {
    for_each = var.source_kms_key_arn != null ? [var.source_kms_key_arn] : []
    content {
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

module "crawler_role" {
  source = "../iam-role"

  team        = var.team
  environment = var.environment
  purpose     = "${var.purpose}-crawler"

  trusted_services = ["glue.amazonaws.com"]

  permission_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  ]

  inline_policies = {
    "source-bucket-read-only" = data.aws_iam_policy_document.crawler_s3_access.json
  }
}

resource "aws_glue_crawler" "this" {
  name          = "${local.name}-crawler"
  database_name = aws_glue_catalog_database.this.name
  role          = module.crawler_role.role_arn
  schedule      = var.crawler_schedule

  s3_target {
    path = "s3://${var.source_bucket_name}/${var.source_prefix}"
  }

  tags = local.tags
}

# ------------------------------------------------------------------
# Athena's own query results need somewhere to land. Reusing
# secure-data-bucket here rather than a raw aws_s3_bucket - query
# results inherit the same encryption/public-access guarantees as
# every other COB-managed bucket, for free, by composition.
# ------------------------------------------------------------------
module "query_results_bucket" {
  source = "../secure-data-bucket"

  team        = var.team
  environment = var.environment
  purpose     = "${var.purpose}-athena-results"
  description = "Athena query result storage for ${local.name}."

  lifecycle_rules = [
    {
      id              = "expire-query-results"
      expiration_days = 30
    }
  ]
}

resource "aws_athena_workgroup" "this" {
  name = "${local.name}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff_per_query
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${module.query_results_bucket.bucket_id}/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = local.tags
}