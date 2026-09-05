
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
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "purpose" {
  type        = string
  description = "Short note describing what this bucket is for (e.g. 'app-logs', 'user-uploads')."

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

# Consumers describe their DATA 
variable "sensitivity" {
  type        = string
  default     = "standard"
  description = "Data sensitivity level for this bucket. 'high' provisions a dedicated, rotated KMS key with an independent audit trail. 'standard' uses AWS-managed SSE-S3 encryption at no additional cost."

  validation {
    condition     = contains(["standard", "high"], var.sensitivity)
    error_message = "sensitivity must be 'standard' or 'high'."
  }
}


variable "kms_key_arn" {
  type        = string
  default     = null
  description = "Optional customer-managed KMS key ARN. If not provided, defaults to AWS-managed SSE-S3 encryption."
}


variable "lifecycle_rules" {
  type = list(object({
    id              = string
    prefix          = optional(string, "")
    expiration_days = number
  }))
  default     = []
  description = "Optional early-expiration rules for specific prefixes, in addition to the baseline transition/cleanup schedule this module always applies (see README)."
}

# Bucket policy grants for principals OUTSIDE what iam-role already
# handles via IAM policy attachments.
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