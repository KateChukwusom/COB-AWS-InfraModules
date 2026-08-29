
##This variable is for the owing team, it feeds into the IAM role name
variable "team" {
  description = "Name of the team"
  type = string
}

#This is for what the role is for, it describes what the role is being used for, must be less than 30 characters
variable "description" {
  description = "Describe your purpose for the role"
  type = string

  validation {
    condition = length(var.description) <20
    error_message = "Description must be 20 characters or fewer"
  }
}

#This is the deployment environment, company's standard is 'dev' and 'prod'.
variable "environment"{
    description = "This is the deployment environment"
    type = string

    validation {
      condition = contains(["dev", "prod"], var.environment)
      error_message = "environment must be either dev or prod"
    }
}


# --- trust role
variable "trusted_principal" {
  type        = string
  description = "Who can assume this role that is a pre-approved AWS service principal."
  validation {
    condition = contains([
      "ec2.amazonaws.com",
      "ecs-tasks.amazonaws.com",
      "lambda.amazonaws.com",
      "glue.amazonaws.com",
      "rds.amazonaws.com",
    ], var.trusted_principal)
    error_message = "trusted_principal must be one of the pre-approved service principals."
  }
}

# access level, this describes the access given to principals
variable "access_level" {
  type        = string
  description = " read-only or read-write."
  validation {
    condition     = contains(["read-only", "read-write"], var.access_level)
    error_message = "access_level must be one of: read-only, read-write."
  }
}

# resource arns created 
variable "resource_arns" {
  type        = list(string)
  description = "The specific resource ARNs this role is attached to"
  validation {
    condition     = length(var.resource_arns) > 0
    error_message = "resource_arns must contain at least one ARN."
  }
}

# resource service, that needs IAM actions
variable "resource_service" {
  type        = string
  description = "Which AWS service resource arns belong to."
  validation {
    condition     = contains(["s3", "dynamodb", "rds", "glue"], var.resource_service)
    error_message = "resource_service must be one of: s3, dynamodb, rds, glue."
  }
}

#An ec2 instance cannot assume an IAM role directly, it needs an instance profile around the role,
#which then get attached to the EC2 instance

variable "create_instance_profile" {
  type = bool
  description = "It checks whether an instance profile needs to be created(For EC2 cases only)"
  default = false
}