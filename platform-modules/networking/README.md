# NETWORKING MODULE

A COB primitive that provisions a VPC with public and private subnets spread across availability zones, ready for other COB primitives to consume.

## What this module owns, and what it doesn't

This module is responsible for network topology only that is VPC, subnets, routing, and optional internet egress via NAT. It does not create security groups. Access control is owned by whichever primitive actually needs it for example compute, since security group rules vary by resource type and are easier to audit when they live next to the thing they're protecting rather than centralized here.

## Opinionated defaults — what you can't configure, and why

| Behavior | Value | Why it's fixed |
| --- | --- | --- |
| CIDR notation | Not exposed to consumers | Every VPC follows the same internal addressing scheme. Keeps the interface simple and prevents misconfigured or overlapping ranges from manual entry. |
| DNS support / hostnames | Always enabled | Required for most AWS-native service integrations; there's no real case for disabling it. |
| Public subnet routing | Always via Internet Gateway | Standard, non-negotiable behavior for a subnet tagged public. |
| Private subnet public IPs | Never assigned | Private means private. |
| Tagging | Always applied | Keeps every COB resource queryable by team/environment for cost tracking and access policies, consistently across all six primitives. |

## Deliberate Directive

Every VPC this module creates uses the same base CIDR range, so two VPCs from this module will have overlapping address space. This is fine until VPC peering or a Transit Gateway is needed between two COB-managed VPCs, at that point this module needs a per-VPC CIDR allocation strategy.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `team` | `string` | — | Team that owns this VPC. Lowercase letters, 2-20 characters. |
| `environment` | `string` | — | One of `dev`, `prod`. |
| `az_count` | `number` | `2` | Number of availability zones to spread subnets across. Must be 2 or 3. |
| `enable_nat_gateway` | `bool` | `false` | Whether to create a NAT gateway for private subnet internet egress. Costs money per hour plus data processing — enable deliberately, not by default. |

## Outputs

| Name | Description |
| --- | --- |
| `vpc_id` | ID of the created VPC. Consumed by `compute`, `rds`, and any module needing to create a security group in this VPC. |
| `vpc_cidr_block` | The VPC's CIDR block. Useful for security group rules scoped to "anything inside this VPC." |
| `public_subnet_ids` | List of public subnet IDs — one per AZ. |
| `private_subnet_ids` | List of private subnet IDs — one per AZ. Typically where `compute` and `rds` should actually place resources. |
| `availability_zones` | The AZ names actually used, in the same order as the subnet ID lists. |

## How to compose it

Call the module once per environment/team combination that needs its own network:

\```hcl
module "networking" {
  source = "../../modules/networking"

  team        = "platform"
  environment = "prod"
  az_count    = 3

  # Only turn this on if something in a private subnet genuinely
  # needs outbound internet access (e.g. pulling packages, calling
  # an external API). Skip it if everything talks only to other
  # AWS services via VPC endpoints.
  enable_nat_gateway = true
}
\```

### Feeding outputs into other COB primitives

Downstream modules should reference `networking`'s outputs rather than hardcoding subnet or VPC IDs:

\```hcl
module "compute" {
  source = "../../modules/compute"

  subnet_ids = module.networking.private_subnet_ids
  vpc_id     = module.networking.vpc_id
  
}

module "rds" {
  source = "../../modules/rds"

  subnet_ids = module.networking.private_subnet_ids
  vpc_id     = module.networking.vpc_id
  # ...
}
\```

Databases and compute resources should almost always land in private subnets. Only put something in a public subnet if it genuinely needs a direct, public-facing presence (e.g. a load balancer).

<!-- ### Dev vs. prod — a realistic pattern

\```hcl
module "networking" {
  source = "../../modules/networking"

  team        = "platform"
  environment = var.environment   # "dev" or "prod", passed from the caller's own tfvars

 ` az_count           = var.environment == "prod" ? 3 : 2
  enable_nat_gateway = var.environment == "prod"
}
\``

##NOTE THIS TO FLAG OFF, ASK QUESTION

Dev environments default to fewer AZs and no NAT gateway (saving cost); prod gets full AZ spread and internet egress enabled. Adjust to your team's actual cost/availability tradeoffs. -->

## What you'll need to build next, per resource type

This module gives you network plumbing only. Before deploying real workloads on top of it, you'll still need:

- A security group in `compute` or `rds`, scoped to `module.networking.vpc_id`
- VPC endpoints, if private-subnet resources need to reach AWS services (S3, DynamoDB, Secrets Manager, etc.) without a NAT gateway
