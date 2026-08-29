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
# Versioning defaults ON. Turning it off is rarely correct for a
# "secure data" primitive — versioning is what protects against
# accidental overwrites/deletes, not just an optional nicety.
# ------------------------------------------------------------------
variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable object versioning on this bucket."
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

# ------------------------------------------------------------------
# Structural type carrying only what's actually needed per rule.
# optional() fields keep the caller from having to specify every
# field for every rule — e.g. a rule with just an expiration
# doesn't need a transition block at all.
# ------------------------------------------------------------------
variable "lifecycle_rules" {
  type = list(object({
    id                        = string
    enabled                   = optional(bool, true)
    prefix                    = optional(string, "")
    expiration_days           = optional(number)
    transition_days           = optional(number)
    transition_storage_class  = optional(string)
  }))
  default     = []
  description = "Lifecycle rules for object expiration and storage class transitions."
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