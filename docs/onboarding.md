# Onboarding: Consuming COB

This guide walks a new engineering team through consuming COB's
Terraform modules for the first time from first access request to a
working `terraform apply`.

If you're looking for why COB is designed the way it is, see
[`module-boundaries.md`](module-boundaries.md) instead. This document
is purely about how to start using it.

---

## 1. Understand what you're consuming vs. what you own

COB provides reusable modules it does not provision or manage
your team's actual infrastructure. Your team is responsible for:

- Creating your own repository (or a clearly separated directory) for
  your infrastructure
- Maintaining your own `environments/dev` and `environments/prod`
  configurations
- Owning your own Terraform state and backend
- Deciding which COB modules to compose, and supplying the values
  specific to your workload

COB's repository should never contain your team's
environment configuration. See the [Repository Structure](../README.md#repository-structure)
section of the main README if this distinction isn't clear yet.

## 2. Set up your own repository structure

At minimum, your team's infrastructure repository should look like:

```text
your-team-infra/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   └── prod/
│       ├── main.tf
│       ├── variables.tf
│       ├── backend.tf
│       └── terraform.tfvars
└── README.md
```

Each environment gets its own state and its own backend configuration, never share state between `dev` and `prod`, and never share state between your team and another team.

## 3. Request access to apply changes (for restricted modules)

Some COB modules are classified as high-privilege and require explicit
access before you can apply changes against them:

| Module | Access required? |
| -------- | ------------------- |
| `networking` | Yes — contact Platform Engineering |
| `identity` | Yes — contact Platform Engineering |
| `database` | Yes — contact Platform Engineering |
| `storage` | No — self-service |
| `compute-ec2` | No — self-service |
| `compute-ecs` | No — self-service |
| `data-platform` | No — self-service |

For restricted modules, Platform Engineering will provision the
underlying access (e.g., IAM permissions scoped to your team's
resources) before you can successfully `apply`. Reach out via
[#platform-engineering] with your team name and the environment(s) you
need access to.

Self-service modules require no special access — you can reference and
apply them immediately, since their blast radius and risk profile are
low enough not to need gatekeeping.

## 4. Reference a COB module

Modules are consumed via a versioned Git reference. Pin to a specific tagged release so your
infrastructure never changes underneath you without your knowledge.

Check each module's own `README.md` for its required inputs, outputs, and any constraints before writing your configuration.

## 5. Compose modules together

Most real infrastructure requires more than one COB module working
together. Downstream modules typically consume the outputs of
upstream ones directly, you rarely need to hardcode IDs by hand:

See [`examples/`](../examples/) in the COB repository for full,
runnable demonstrations of common module combinations.

## 6. Set up your backend

Your `environments/dev/backend.tf` and `environments/prod/backend.tf`
should point to your own team's state storage, in your own reserved
key path. If your organization uses a shared state backend, your key
should follow the convention:

{team}/{component}/{environment}/terraform.tfstate

## 7. Apply

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

Always review the `plan` output before applying, especially for any
module classified as high-privilege. Never let CI/CD auto-apply
against `prod` without a human review step.
