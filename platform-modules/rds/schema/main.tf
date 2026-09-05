# ------------------------------------------------------------------
# This resource type comes from the community "postgresql" provider
# (cyrilgdn/postgresql), NOT the AWS provider. It connects to the
# database directly over the network and issues real SQL - the AWS
# provider has no concept of schemas, since AWS's control plane never
# looks inside the running engine.
#
# The postgresql provider itself is NOT configured in this module.
# Provider configuration must happen in the ROOT module that calls
# this one, and be passed down explicitly via the `providers`
# argument - Terraform does not allow a reusable child module to
# silently configure its own provider connection details, since that
# would hide exactly the kind of network/credential dependency a
# caller needs to be aware of before using this module. See this
# module's README for the required root-level setup.
# ------------------------------------------------------------------
resource "postgresql_schema" "this" {
  for_each = { for s in var.schemas : s.name => s }

  name  = each.value.name
  owner = each.value.owner

  database = var.database_name
}