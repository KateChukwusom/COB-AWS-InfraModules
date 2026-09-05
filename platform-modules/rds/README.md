# `rds`

## Purpose

A COB primitive that provisions a managed PostgreSQL database with no path to public exposure, no plaintext credentials anywhere in a consumer's Terraform, and environment-aware safety behavior. This document describes the engineering reasoning behind the module's scope, including what it deliberately does not do.

## Engine scope: PostgreSQL only

This module provisions PostgreSQL exclusively. There is no `engine` input. A variable with exactly one legitimate value is not meaningfully a variable — it's a fixed fact about the module wearing a caller-facing input's clothing. Removing it makes that fact explicit rather than implied by convention. Teams requiring a different engine are not currently served by this primitive.

## Credentials: generated and owned entirely by AWS

This module does not generate, accept, or expose a database password at any point.

```hcl
manage_master_user_password = true
```

This single argument replaces what would otherwise require a hand-built chain of resources: a random password generator, a Secrets Manager secret, and a secret version to store the value inside it. AWS's native implementation does all of this internally — generating the password, storing it in Secrets Manager, and managing rotation — without any of that machinery needing to exist in this module's own code.

There is no `password` variable to supply, no password ever appears in a `.tfvars` file or a module call, and no password is ever readable from Terraform state as plaintext. Anything needing to actually connect to the database must separately hold IAM permission to read the secret from Secrets Manager at the moment it connects. The credential never travels through this module's outputs; only a pointer to where it lives does.

## Network isolation: inherited from `networking`, and its real limitation

This module requires subnets and a VPC from the `networking` module — it does not create either itself. This means a limitation documented in `networking`'s own README applies here directly, and is worth restating in this module's own context rather than leaving a reader to discover it elsewhere:

**Every VPC created by `networking` uses the same hardcoded CIDR block, regardless of which team calls it.** Two different teams' databases, provisioned through this module, will very likely sit inside VPCs with *identical, overlapping IP address ranges*. This is not a naming collision — the database's own identifier is safely unique per team (see below) — this is the underlying network address space itself being duplicated.

**Why this is safe in the vast majority of cases:** a VPC is a fully isolated network namespace. Two VPCs sharing the exact same CIDR range cause no operational problem whatsoever as long as those two VPCs never need to route traffic to each other directly. Team A's database and Team B's database, each in their own `10.0.0.0/16`, operate completely independently — nothing inside one VPC can reach or even resolve an address inside the other.

**Where this becomes a real, blocking problem:** the moment two COB-provisioned VPCs need to talk to each other — through VPC peering, a Transit Gateway, or any cross-VPC routing — identical, overlapping CIDR ranges make that connection impossible to establish. Routing cannot disambiguate two networks both claiming `10.0.0.0/16`.

**This module does not resolve that limitation on its own, because it isn't this module's limitation to resolve.** It is inherited entirely from `networking`, and fixing it means giving `networking` a genuine per-VPC CIDR allocation strategy (e.g. a coordinated index feeding `cidrsubnet()`, rather than a single hardcoded block) — tracked as a known limitation there, not solved here. Any database provisioned by this module inherits that same constraint for as long as it remains open.

## Identity and naming: not the same problem as the IP-collision issue above

Separately from network addressing, this module's database identifier is composed from `team`, `environment`, and `purpose`:


Two different teams naturally produce two different identifiers, since `team` itself is part of the string — this is safely unique without needing a random suffix, unlike `networking`'s CIDR block, which is identical regardless of caller. Naming and IP addressing are two independent concerns in this platform: one is solved here, the other remains open, inherited from `networking`, as described above.

## Scope boundary: infrastructure, not schema

This module creates one thing inside the database engine: an empty, named database (`database_name`). It does not create schemas, tables, roles, or any other structure inside that database — provisioning the server is an AWS API operation, while creating a schema requires connecting directly to the running engine and executing SQL, which is a fundamentally different kind of operation with different operational requirements (network reachability to the database, live credentials at apply time, a separate change lifecycle from infrastructure itself).

**A dedicated submodule, `rds/schema`, exists for this purpose.** It is not called automatically by this module — it requires its own root-level provider configuration and network reachability into the database's private subnet. See `modules/rds/schema/README.md` for full details and required setup.

## What you can't configure, and why

| Behavior | Value | Why it's fixed |
|---|---|---|
| Public accessibility | Always `false` | No legitimate case for a database provisioned by this primitive to be reachable outside the VPC. |
| Storage encryption | Always `true` | Matches the "encryption is never optional" principle applied across every COB primitive touching data at rest. |
| Engine | Always PostgreSQL | See "Engine scope" above. |
| Master password | Never caller-supplied | Generated and owned entirely by AWS. See "Credentials" above. |
| Network access method | Named security groups only | No `cidr_blocks` path exists. |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `team` | `string` | — | Owning team. |
| `environment` | `string` | — | One of `dev`, `staging`, `prod`. |
| `purpose` | `string` | — | Short slug describing what this database serves. |
| `vpc_id` | `string` | — | Required. From `networking`'s `vpc_id` output. |
| `subnet_ids` | `list(string)` | — | Required, at least 2. From `networking`'s `private_subnet_ids`. |
| `allowed_security_group_ids` | `list(string)` | — | Required, at least 1. Security groups permitted to connect. |
| `engine_version` | `string` | — | PostgreSQL version, e.g. `"16.4"`. |
| `instance_class` | `string` | `"db.t3.micro"` | One of the approved sizes. |
| `allocated_storage` | `number` | `20` | GB, between 20 and 1000. |
| `multi_az` | `bool` | `false` | Standby replica in a second AZ. Doubles cost. |
| `backup_retention_period` | `number` | `7` | Days, between 1 and 35. |
| `database_name` | `string` | — | Initial empty database name. Schema/tables are out of scope — see above. |
| `master_username` | `string` | `"cob_admin"` | No corresponding password input exists. |
| `tags` | `map(string)` | `{}` | Additional tags. |

## Outputs

| Name | Description |
|---|---|
| `db_instance_endpoint` | Hostname/port for application connections. |
| `db_instance_id` | Database identifier. |
| `security_group_id` | This database's security group ID. |
| `secret_arn` | ARN of the AWS-managed Secrets Manager secret holding the credential. The credential itself is never exposed as an output. |

## Composition

```hcl
module "networking" {
  source = "../../modules/networking"

  team        = "data"
  environment = "prod"
}

module "app_compute" {
  source = "../../modules/compute"
  # ...
}

module "orders_db" {
  source = "../../modules/rds"

  team        = "data"
  environment = "prod"
  purpose     = "orders"

  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids

  allowed_security_group_ids = [module.app_compute.security_group_id]

  engine_version = "16.4"
  instance_class = "db.t3.small"
  database_name  = "orders"
}
```

Anything connecting to `orders_db` reads its credential directly from Secrets Manager at runtime, using `module.orders_db.secret_arn` to locate it, with its own IAM permission to call `secretsmanager:GetSecretValue` — never from a Terraform output or state file.

For creating schemas inside `orders_db` once it exists, see `modules/rds/schema/README.md`.

## Known limitations

- VPC/subnet IP address ranges may overlap between teams : Inherited directly from `networking`'s hardcoded CIDR block — see "Network isolation" above. Safe until cross-VPC connectivity (peering, Transit Gateway) is required; not yet resolved.
- Schema and table creation are out of scope for this module : See the dedicated `rds/schema` submodule.
- PostgreSQL only: No other engine is currently supported.
- No parameter group customization : Engine-level settings rely entirely on RDS's default parameter group.
- No cross-region read replica support

## Cross-Region Read Replicas

A **read replica** is a continuously synced, read-only copy of a
database. It receives all writes made to the primary via automatic
replication, but only ever serves `SELECT` queries — never writes.
This lets read-heavy traffic (reporting, analytics, dashboards) be
offloaded from the primary instance, keeping it free to handle writes
and critical transactional queries.

A **cross-region** read replica takes this further by placing that
replica in a different AWS region than the primary (e.g., primary in
`us-east-1`, replica in `eu-west-1`), rather than the same region.
This is useful for three reasons:

- **Disaster recovery** — if an entire AWS region goes down, a
  same-region replica goes down with it. A cross-region replica
  survives and can be promoted into a new standalone primary.
- **Lower latency for distributed users** — users in a different
  geography can read from a nearby replica instead of round-tripping
  to a primary on another continent.
- **Data residency/compliance** — some regulations require certain
  data to be readable from, or stored within, a specific region.

### Why COB's `database` module doesn't support this yet

Cross-region replication introduces real complexity: replica lag
handling, promoting a replica during failover, cross-region
networking, and cross-region KMS key handling (since KMS keys are
region-scoped, encrypted data can't simply be replicated across
regions without additional key configuration).

COB v1 intentionally provisions single-region database instances
only. Teams with a genuine cross-region requirement should raise it
with Platform Engineering — this is a planned direction for a future
version, not a gap that should be worked around manually.
