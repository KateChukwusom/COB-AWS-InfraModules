variable "team" {
  type        = string
  default     = "internal-tools"
  description = "Team this example is provisioned for."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Deployment environment for this example."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}