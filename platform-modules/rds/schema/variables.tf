# ------------------------------------------------------------------
# This submodule connects DIRECTLY to a running PostgreSQL database
# and executes real SQL - a fundamentally different operation from
# the parent rds module, which only talks to AWS's API. See this
# module's README for what that requires operationally.
# ------------------------------------------------------------------

variable "schemas" {
  type = list(object({
    name  = string
    owner = optional(string)
  }))
  description = "Schemas to create inside the target database. 'owner' defaults to the connecting user if omitted."

  validation {
    condition = alltrue([
      for s in var.schemas : can(regex("^[a-z_][a-z0-9_]{0,62}$", s.name))
    ])
    error_message = "Each schema name must start with a lowercase letter or underscore, and contain only lowercase letters, numbers, and underscores."
  }
}

variable "database_name" {
  type        = string
  description = "The database these schemas are created inside. Must match the rds module's database_name."
}