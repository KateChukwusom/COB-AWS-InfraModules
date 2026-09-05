/*Because an s3 bucket must be globally unique, A deliberate, readable name alone 
cannot guarantee that uniqueness so the random suffix is there to make it unique
 */
resource "random_id" "suffix" {
  byte_length = 4
}

/* This local block exist to make the resource to be created globally unique 
easily identified by name and tags */
locals {
  bucket_name = "cob-${var.team}-${var.environment}-${var.purpose}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Team        = var.team
    Environment = var.environment
    ManagedBy   = "COB"
    Description = var.description
  })
}

resource "aws_s3_bucket" "COB_s3_bucket" {
  bucket = local.bucket_name

  tags = merge(local.tags, { Name = local.bucket_name })
}

# Versioning protects against overwrite and
# delete mistakes - this module doesn't offer a way to turn that
# protection off. Pairs unconditionally with the lifecycle baseline
# below, which is what keeps versioning's storage cost bounded.

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption is NEVER optional, only which key is used varies.
# No kms_key_arn -> AWS-managed SSE-S3. A kms_key_arn -> SSE-KMS
# with the caller's own key. There is no code path that produces
# an unencrypted bucket.
/* */
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# All settings here are Hardcoded to enforce standards 
/* */
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}




# This encodes COB's default retention/cost policy rather than leaving
# every team to invent their own transition schedule from scratch.
# Callers may ADD prefix-specific early-expiration rules via
# var.lifecycle_rules, but cannot alter or remove this baseline.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  depends_on = [aws_s3_bucket_versioning.this]
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "cob-default-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

  }

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      expiration {
        days = rule.value.expiration_days
      }
    }
  }
}

# Only created when sensitivity = "high". The module owns this key's
# entire lifecycle - creation, rotation, and safe deletion handling -
# rather than accepting a pre-existing key ARN from the caller. A
# consumer never needs to have touched KMS directly to use this
# module correctly.
resource "aws_kms_key" "bucket_key" {
  count = var.sensitivity == "high" ? 1 : 0

  description = "KMS key for ${local.bucket_name} (high-sensitivity bucket)"

  deletion_window_in_days = 30
  enable_key_rotation = true

  tags = local.tags
}
# A KMS key's real identifier is an opaque UUID, it is not something a
# human can recognize in the console. This alias exists purely for
# discoverability: anyone browsing KMS sees a readable name tied to
# the bucket it protects.
resource "aws_kms_alias" "bucket_key" {
  count = var.sensitivity == "high" ? 1 : 0

  name          = "alias/${local.bucket_name}-key"
  target_key_id = aws_kms_key.bucket_key[0].key_id
}

locals {
  
  sse_algorithm = var.sensitivity == "high" ? "aws:kms" : "AES256"
  kms_key_arn   = var.sensitivity == "high" ? aws_kms_key.bucket_key[0].arn : null
}

# Encryption itself is never optional, this resource always exists,
# on every bucket.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = true
  }
}
# This should be Only generated if the caller actually granted external principals.

/* */
data "aws_iam_policy_document" "bucket_policy" {
  count = length(var.allowed_principal_arns) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*"
    ]

    principals {
      type        = "AWS"
      identifiers = var.allowed_principal_arns
    }
  }
}

/* */
resource "aws_s3_bucket_policy" "this" {
  count  = length(var.allowed_principal_arns) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy[0].json
}