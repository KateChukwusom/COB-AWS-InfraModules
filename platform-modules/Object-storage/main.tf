/*Because an s3 bucket must be globally unique, A deliberate, readable name alone 
cannot guarantee that uniqueness so The random suffix is
# therefore not optional here the way it was treated as a fallback
# in iam-role — it's structurally required every time.
 */
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "cob-${var.team}-${var.environment}-${var.purpose}-${random_id.suffix.hex}"

  tags = merge(var.tags, {
    Team        = var.team
    Environment = var.environment
    ManagedBy   = "COB"
    Description = var.description
  })
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  tags = merge(local.tags, { Name = local.bucket_name })
}

# ------------------------------------------------------------------
# Versioning is caller-toggleable, but defaults on (see variables.tf).
# ------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ------------------------------------------------------------------
# Encryption is NEVER optional — only which key is used varies.
# No kms_key_arn -> AWS-managed SSE-S3. A kms_key_arn -> SSE-KMS
# with the caller's own key. There is no code path that produces
# an unencrypted bucket.
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
# Hardcoded, all four settings, no exceptions, no variable exposing
# this to callers. A "secure data bucket" that lets someone flip
# public access back on defeats the module's entire purpose. If a
# genuine public-hosting use case ever arises, it belongs in a
# separate, explicitly-named module (e.g. public-website-bucket),
# not as a quiet toggle here.
# ------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------
# count, not for_each: this is an on/off decision (are there ANY
# lifecycle rules at all), not a loop over distinct named items in
# its own right — the actual looping happens inside, via the
# dynamic "rule" block below.
# ------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition_days != null ? [rule.value.transition_days] : []
        content {
          days          = transition.value
          storage_class = rule.value.transition_storage_class
        }
      }
    }
  }
}

# ------------------------------------------------------------------
# Only generated if the caller actually granted external principals.
# Uses the same aws_iam_policy_document data source pattern as
# iam-role's trust policy — structural validation before AWS ever
# sees raw JSON, same reasoning as before.
# ------------------------------------------------------------------
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

resource "aws_s3_bucket_policy" "this" {
  count  = length(var.allowed_principal_arns) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy[0].json
}