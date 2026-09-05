# Team that owns this database. 
variable "team" {
  type        = string
  description = "Team that owns this database."

  validation {
    condition     = can(regex("^[a-z]{2,20}$", var.team))
    error_message = "team must be 2-20 characters, lowercase letters, and hyphens only."
  }
}

/* This is the environment the database is to be deployed in*/
variable "environment" {
  type        = string
  description = "Deployment environment."

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev or prod."
  }
}

# The purpose for setting up the database, should be 2-20 characters
variable "purpose" {
  type        = string
  description = "Short description of  what this database serves (e.g. 'orders')"

  validation {
    condition     = can(regex("^[a-z]{2,20}$", var.purpose))
    error_message = "purpose must be 2-20 characters, lowercase letters, and hyphens only."
  }
}

/* Which VPC the database's security group is attached to. Must come from
the networking module's vpc_id output. Please note - this module
does not create its own network.*/

variable "vpc_id" {
  type        = string
  description = "VPC ID from the networking module's vpc_id output."
}

/* Which subnets the database itself is placed into. Must come from
 networking's private_subnet_ids output. AWS requires at least 2,
 across different AZs, to build a DB subnet group. */
variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs from the networking module - must be private_subnet_ids."

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet_ids are required, across different AZs, for the DB subnet group."
  }
}

/* Only Security group IDs allowed to connect to this database. Pease note: there is no CIDR-based input..Must contain at least one entry */
variable "allowed_security_group_id" {
  type        = list(string)
  description = "Security group IDs permitted to connect to this database (e.g. compute's security_group_id)."

  validation {
    condition     = length(var.allowed_security_group_id) > 0
    error_message = "At least one allowed_security_group_id is required."
  }
}

# Specific engine version, e.g. '16.4' for postgres.
variable "engine_version" {
  type        = string
  description = "Database engine version."
}

# Server size. Limited to an approved list to prevent accidental
# oversized/expensive provisioning.
variable "instance_class" {
  type        = string
  default     = "db.t3.micro"
  description = "RDS instance class."

  validation {
    condition     = contains(["db.t3.micro", "db.t3.small", "db.t3.medium", "db.r6g.large"], var.instance_class)
    error_message = "instance_class must be one of the approved sizes."
  }
}

# Storage size in GB. Bounded to prevent typos from provisioning
# far more storage (and cost) than intended.
variable "allocated_storage" {
  type        = number
  default     = 20
  description = "Allocated storage in GB."

  validation {
    condition     = var.allocated_storage >= 20 && var.allocated_storage <= 1000
    error_message = "allocated_storage must be between 20 and 1000 GB."
  }
}

# Whether to run a standby replica in a second AZ. Doubles cost -
# defaults off, must be turned on deliberately.
variable "multi_az" {
  type        = bool
  default     = false
  description = "Whether to deploy a standby replica in a second AZ."
}

# How many days automated backups are kept. 35 is AWS's own maximum.
variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated backups."

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 1 and 35 days."
  }
}

# Name of the initial database created inside the engine. Must start
# with a letter; only letters, numbers, underscores allowed.
variable "database_name" {
  type        = string
  description = "Initial database name to create."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must start with a letter and contain only letters, numbers, and underscores."
  }
}

# Master username only. There is NO password variable anywhere in
# this file - the password is generated internally in main.tf.
variable "master_username" {
  type        = string
  default     = "cob_admin"
  description = "Master username. The password is generated internally, never supplied here."
}

# Extra tags, merged with the module's own required tags.
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with the module's own required tags."
}