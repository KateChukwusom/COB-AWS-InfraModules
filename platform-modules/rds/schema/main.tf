
# This resource type comes from the community "postgresql" provider
# (cyrilgdn/postgresql), NOT the AWS provider. It connects to the
# database directly over the network and issues real SQL 
#
# The postgresql provider itself is NOT configured in this module.
# Provider configuration must happen in the ROOT module that calls
# this one, and be passed down explicitly via the `providers`
# argument 
resource "postgresql_schema" "this" {
  for_each = { for s in var.schemas : s.name => s }

  name  = each.value.name
  owner = each.value.owner

  database = var.database_name
}