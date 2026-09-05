# `rds/schema`

## Purpose

A submodule of `rds` that creates schemas inside an already-provisioned
PostgreSQL database. This is intentionally separate from the parent
`rds` module and is not called automatically by it.

## Why this is a separate module, not part of `rds` itself

`rds` provisions infrastructure by talking to AWS's control plane —
Terraform calls AWS's API, AWS handles it, and nothing about that
interaction requires reaching the database over the network. Creating a
schema is different in kind: it requires connecting **directly to the
running PostgreSQL engine** and executing real SQL. AWS's API has no
involvement in that operation at all.

Because of this difference, using this module has real operational
requirements that `rds` alone does not:

- **Network reachability.** Wherever `terraform apply` runs for this
  module must be able to reach the database over the network — inside
  the VPC, through a VPN, a bastion host, or a CI runner provisioned
  inside the same network. This module cannot be applied from an
  arbitrary machine the way `rds` itself can.
- **Live credentials at apply time.** Connecting requires the database's
  actual username and password, read from Secrets Manager at the moment
  Terraform runs — not merely a reference to where they live.
- **Provider configuration, done by the caller, not this module.**
  Terraform does not allow a reusable module to silently configure its
  own provider connection. The `postgresql` provider must be configured
  in your root module, using the `rds` module's outputs, and passed into
  this module explicitly.

## Required root-level setup

```hcl
module "orders_db" {
  source = "../../modules/rds"
  # ... as normal
}

data "aws_secretsmanager_secret_version" "orders_db_credentials" {
  secret_id = module.orders_db.secret_arn
}

locals {
  orders_db_creds = jsondecode(data.aws_secretsmanager_secret_version.orders_db_credentials.secret_string)
}

provider "postgresql" {
  alias    = "orders_db"
  host     = module.orders_db.db_instance_endpoint
  port     = 5432
  username = local.orders_db_creds.username
  password = local.orders_db_creds.password
  sslmode  = "require"
}

module "orders_schema" {
  source = "../../modules/rds/schema"

  providers = {
    postgresql = postgresql.orders_db
  }

  database_name = "orders"
  schemas = [
    { name = "app" },
    { name = "reporting", owner = "reporting_role" }
  ]
}
```

**This root configuration must run from somewhere that can actually
reach the database** — the private subnet it lives in has no public
route by design (see `rds`'s own README). In practice this usually means
running this specific `apply` from a CI runner or bastion host deployed
inside the same VPC, not from an arbitrary developer machine over the
open internet.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `database_name` | `string` | — | Must match the `rds` module's `database_name`. |
| `schemas` | `list(object({ name = string, owner = optional(string) }))` | — | Schemas to create. `owner` defaults to the connecting user if omitted. |

## Outputs

| Name | Description |
|---|---|
| `schema_names` | Names of the schemas created. |

## Known limitations

- Table, role, and grant management are not yet implemented — only
  schema creation. Extending this module to cover those is a natural
  next step, following the same connection pattern established here.
- This module has no awareness of application-level migrations. For
  ongoing table/column changes as an application evolves, a dedicated
  migration tool (Flyway, `golang-migrate`, framework-native migrations)
  remains the recommended approach — this module is intended for
  one-time schema bootstrapping, not ongoing schema evolution.