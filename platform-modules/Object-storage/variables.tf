# ------------------------------------------------------------------
# Same identity convention as every other COB primitive: team +
# environment drive naming and tagging consistently across modules.
# ------------------------------------------------------------------
variable "team" {
  type        = string
  description = "Team that owns this bucket."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.team))
    error_message = "team must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment for this bucket."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ------------------------------------------------------------------
# Short, name-safe identifier only — NOT a place for long
# descriptions. Full human-readable context belongs in the
# `description` tag below, not here, since this feeds directly into
# the bucket name and S3 bucket names have a hard 63-character
# global limit.
# ------------------------------------------------------------------
variable "purpose" {
  type        = string
  description = "Short slug describing what this bucket is for (e.g. 'app-logs', 'user-uploads')."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.purpose))
    error_message = "purpose must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "description" {
  type        = string
  default     = ""
  description = "Optional longer human-readable description, stored as a tag rather than in the bucket name."
}

# ------------------------------------------------------------------
# Consumers describe their DATA, not their encryption implementation.
# A team knows whether what they're storing is sensitive; they
# shouldn't need to know what SSE-KMS is, or go create a key
# themselves before they can use this module. The module derives the
# actual encryption mechanism from this single business-level input.
# ------------------------------------------------------------------
variable "sensitivity" {
  type        = string
  default     = "standard"
  description = "Data sensitivity level for this bucket. 'high' provisions a dedicated, rotated KMS key with an independent audit trail. 'standard' uses AWS-managed SSE-S3 encryption at no additional cost."

  validation {
    condition     = contains(["standard", "high"], var.sensitivity)
    error_message = "sensitivity must be 'standard' or 'high'."
  }
}

# ------------------------------------------------------------------
# null means "use AWS's own managed key (SSE-S3 / aws/s3)". Passing
# a real KMS key ARN upgrades encryption to SSE-KMS, giving the
# caller their own key policy and audit trail via CloudTrail.
# Either way, encryption is never optional — only the KEY differs.
# ------------------------------------------------------------------
variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Optional customer-managed KMS key ARN. If not provided, defaults to AWS-managed SSE-S3 encryption."
}

# versioning_enabled has been removed entirely - versioning is
# unconditional on every bucket this module creates. See main.tf.

variable "lifecycle_rules" {
  type = list(object({
    id              = string
    prefix          = optional(string, "")
    expiration_days = number
  }))
  default     = []
  description = "Optional early-expiration rules for specific prefixes, in addition to the baseline transition/cleanup schedule this module always applies (see README)."
}

# ------------------------------------------------------------------
# Bucket policy grants for principals OUTSIDE what iam-role already
# handles via IAM policy attachments. Most access should flow
# through iam-role's permission_policy_arns / inline_policies
# instead — this exists for cases like cross-account access or
# service principals (e.g. CloudTrail, an ELB access-log delivery
# service) that need a bucket policy specifically, not an IAM policy.
# ------------------------------------------------------------------
variable "allowed_principal_arns" {
  type        = list(string)
  default     = []
  description = "Principal ARNs granted read/write access via bucket policy, beyond what IAM role policies already provide."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with the module's own required tags."
}