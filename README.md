
# COB AWS Internal Infrastructure

COB is Beejan Technologies' internal Terraform module library, a set of opinionated, reusable primitives that teams compose to provision AWS infrastructure consistently, without every team reinventing networking, IAM, and storage decisions from scratch.

## Design philosophy

Every module in this library is built against four questions, applied deliberately rather than left to default behavior:

- **Encapsulation** — what does the consumer actually need to decide, and what should the module own outright? A module is only worth naming separately from its underlying AWS resource if it adds real abstraction on top of it.

- **Privilege** — for any module touching access or security posture, the strongest guardrail is usually not exposing the dangerous knob at all, rather than trying to validate every possible misuse of it.

- **Volatility** — inputs that change often per consumer stay flexible; decisions that should never vary (a secure bucket staying private, a role never getting `AdministratorAccess`) get hardcoded, not merely defaulted.

- **Ownership** — each primitive has a clear boundary of responsibility. When two primitives could plausibly own the same concern (e.g. bucket access — `secure-data-bucket` vs. `iam-role`), one is picked deliberately and the other documents the exception path.

Every module's own README documents its specific answers to these four questions — what it exposes, what it hardcodes, and why.

## Primitives

| Primitive | Purpose |
| --- | --- |
| `networking` | VPC, public/private subnets across AZs, optional NAT egress. |
| `iam-role` | IAM roles with trust policies, managed/inline permission policies, permission boundaries. |
| `secure-data-bucket` | Private, encrypted S3 storage with lifecycle management. |
| `compute` | EC2 / ECS workload provisioning, consuming `networking` + `iam-role`. |
| `rds` | Managed relational database, consuming `networking` + `iam-role`. |
| `data-platform` | Composition module wiring the above primitives into complete, opinionated stacks per data classification. |

Each module directory contains its own `variables.tf`, `main.tf`, `outputs.tf`, and `README.md`.

## Using a Module

Reference the module by relative path and supply its required inputs — see each module's own README for the full input/output reference and composition examples:

```hcl
module "networking" {
  source = "../../modules/networking"

  team        = "platform"
  environment = "prod"
}
```

## Naming and tagging convention

Every primitive follows the same identity convention: `team` and `environment` are required inputs on every module, validated the same way, and every resource gets `Team`, `Environment`, and `ManagedBy = COB` tags automatically, not consumer-extensible, so every resource in the platform is queryable consistently regardless of which team created it.

## Status

All six primitives are built and available for use.

Kindly reach out to the platform team at verge of more clarification.
