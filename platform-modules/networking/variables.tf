
# team identify who owns this VPC 
variable "team" {
  type        = string
  description = "Team that owns this VPC."

# this validation checks against what is required to be an input
  validation {
    condition     = can(regex("^[a-z-]{2,20}$", var.team))
    error_message = "team must be 2-20 characters, lowercase letters only."
  }
}

# environment identfies where it lives
variable "environment" {
  type        = string
  description = "Deployment environment for this VPC."

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be of: dev, prod."
  }
}


/*This COB's VPC decides to follow the same addressing convention so, az_count controls 
subnets only, therefore it deliberately does not accept raw CIDR notation from consumers
. CIDR nottation is entirely owned by the module*/

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of availability zones to spread subnets across."

# This validates that the available zones inputed by the consumer must be 2 or 3.
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

/*The default of this is false because NAT gateways cost money per hour,
however the consumer put have considered the need to opt in deliberately */

variable "enable_nat_gateway" {
  type        = bool
  default     = false
  description = "Whether to create a NAT gateway for private subnet internet egress."
}