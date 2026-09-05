variable "team" {
  type        = string
  description = "Team that owns this data platform instance."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.team))
    error_message = "team must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "purpose" {
  type        = string
  description = "Short slug describing what this catalog exposes (e.g. 'orders-analytics')."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.purpose))
    error_message = "purpose must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# ------------------------------------------------------------------
# This module never creates or owns the data being cataloged. It
# only consumes an existing secure-data-bucket's identity - the
# ownership boundary is enforced structurally, the same way compute
# and rds refuse to create their own VPC.
# ------------------------------------------------------------------
variable "source_bucket_name" {
  type        = string
  description = "Bucket name from secure-data-bucket's bucket_id output."
}

variable "source_bucket_arn" {
  type        = string
  description = "Bucket ARN from secure-data-bucket's bucket_arn output. Used to scope the crawler's IAM policy narrowly to this bucket only."
}

variable "source_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN from secure-data-bucket's kms_key_arn output, if the source bucket uses sensitivity = \"high\". Null for standard-sensitivity buckets."
}

variable "source_prefix" {
  type        = string
  default     = ""
  description = "Prefix within the source bucket where data lives (e.g. 'events/'). Empty crawls the whole bucket."
}

# ------------------------------------------------------------------
# Optional. Null means the crawler only runs when manually triggered
# (via console, CLI, or an external orchestrator) - not scheduled.
# Cron-driven crawling has a real cost (each run scans S3), so
# scheduling is opt-in, not a default.
# ------------------------------------------------------------------
variable "crawler_schedule" {
  type        = string
  default     = null
  description = "Optional cron expression (e.g. 'cron(0 6 * * ? *)') for automatic crawler runs. Omit to run only on manual trigger."
}

# ------------------------------------------------------------------
# A real cost-control lever, not a nicety. Athena bills per byte
# scanned - an unbounded, accidentally broad query (missing a WHERE
# clause, scanning a huge unpartitioned table) can produce a
# surprising bill. This caps it structurally, per query, at the
# workgroup level.
# ------------------------------------------------------------------
variable "bytes_scanned_cutoff_per_query" {
  type        = number
  default     = 1073741824  # 1 GB
  description = "Maximum bytes a single Athena query may scan before being stopped. Default 1 GB; raise deliberately for known large-query workloads."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with the module's own required tags."
}