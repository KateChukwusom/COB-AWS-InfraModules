
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



