# ------------------------------------------------------------------
# Same identity convention as every other COB primitive.
# ------------------------------------------------------------------
variable "team" {
  type        = string
  description = "Team that owns this compute resource."

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
  description = "Short slug describing what this compute resource runs (e.g. 'api', 'worker')."

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.purpose))
    error_message = "purpose must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# ------------------------------------------------------------------
# Required, not defaulted. This module refuses to create its own VPC
# or subnets - it consumes networking's outputs directly. Passing
# nothing here should fail loudly, not silently fall back to a
# default VPC.
# ------------------------------------------------------------------
variable "vpc_id" {
  type        = string
  description = "VPC ID from the networking module's vpc_id output."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs from the networking module - typically private_subnet_ids."

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "At least one subnet_id is required."
  }
}

# ------------------------------------------------------------------
# Required. This module refuses to create its own IAM role either -
# identity comes from iam-role's instance_profile_name output. Same
# ownership discipline as the VPC/subnet inputs above.
# ------------------------------------------------------------------
variable "instance_profile_name" {
  type        = string
  description = "Instance profile name from the iam-role module's instance_profile_name output."
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type."

  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large"], var.instance_type)
    error_message = "instance_type must be one of the approved sizes: t3.micro, t3.small, t3.medium, t3.large."
  }
}

variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum number of instances in the Auto Scaling Group."
}

variable "max_size" {
  type        = number
  default     = 3
  description = "Maximum number of instances in the Auto Scaling Group."
}

variable "desired_capacity" {
  type        = number
  default     = 1
  description = "Desired number of instances in the Auto Scaling Group."
}

# ------------------------------------------------------------------
# Structural type - each rule is a distinct ingress path. Validation
# below blocks the one ingress pattern that's almost always a
# mistake: SSH open to the entire internet.
# ------------------------------------------------------------------
variable "ingress_rules" {
  type = list(object({
    description              = string
    port                     = number
    protocol                 = optional(string, "tcp")
    cidr_blocks              = optional(list(string), [])
    source_security_group_id = optional(string)
  }))
  default     = []
  description = "Ingress rules for this compute resource's security group."

  validation {
    condition = alltrue([
      for rule in var.ingress_rules :
      !(rule.port == 22 && contains(rule.cidr_blocks, "0.0.0.0/0"))
    ])
    error_message = "SSH (port 22) may not be opened to 0.0.0.0/0. Use a bastion, SSM Session Manager, or a specific CIDR instead."
  }
}

variable "user_data" {
  type        = string
  default     = ""
  description = "Optional user data script run on instance launch."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with the module's own required tags."
}