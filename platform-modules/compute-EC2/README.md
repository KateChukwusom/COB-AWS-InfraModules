# `compute - EC2`

## Purpose

A COB module that provisions EC2 compute capacity behind an Auto
Scaling Group, using a launch template as the reusable blueprint for
every instance it creates. This document describes the engineering
reasoning behind the module's structure that is what it owns, what it
deliberately refuses to own, and why an Auto Scaling Group was chosen
over a normal EC2 instance.

## What this module owns, and what it doesn't

This module is responsible for what runs, and how it's reached over
the network that is instance sizing, scaling boundaries, security group
rules, and startup behavior. It does not create a VPC, subnets, or an
IAM role. `vpc_id`, `subnet_ids`, and `instance_profile_name` are all
required inputs with no default that is  if a consumer has not first provisioned
`networking` and `iam-role` and wired their outputs into this module, it
fails validation immediately.

Security groups are created and owned here, not in `networking`. Access
rules vary by what they're protecting, and a consumer trying to
understand "what can reach this instance" should be able to answer that
by reading this module alone, without cross-referencing a separate
networking configuration for a security group that may or may not apply.

## Why an Auto Scaling Group, not a single EC2 instance

A bare EC2 instance has a fixed identity and no self-correcting behavior.
If it fails a health check or the underlying hardware is retired, nothing
in AWS reacts that is the nobody knows

About the Auto scaling group; the launch template is a blueprint, it consists of AMI, instance type, security group, IAM profile, startup script and not an instance itself.
The Auto Scaling Group is a target state: how many instances should exist
right now, and the boundaries that state can never cross. AWS
continuously enforces that target state independently of Terraform.
It maintains the health and availabiity of your instances using EC2 health checks and replaces terminated or impaired instamced to maintan your desired capacity.

This is what makes "min_size", "max_size", and "desired_capacity"
meaningful as separate inputs: they express not just a current count, but
the boundaries a workload is allowed to operate within.

## Network access: validated, not merely documented

`ingress_rules` accepts a consumer-defined list of rules, but SSH open to the entire
internet is blocked.

Egress is intentionally left open to `0.0.0.0/0` to avoid operational complexity
for now, that may be an enhancement in the future.

## Instance sizing: bounded by design

`instance_type` is restricted to an approved list rather than accepting
any AWS-valid string. This is a cost-control decision, not a technical
requirement. The restriction exists so an unconsidered choice cannot
provision something significantly oversized and expensive without at
least one deliberate checkpoint.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `team` | `string` | — | Owning team. Lowercase letters, numbers, hyphens, 2-20 characters. |
| `environment` | `string` | — | One of `dev`, `staging`, `prod`. |
| `purpose` | `string` | — | Short slug describing the workload (e.g. `api`, `worker`). |
| `vpc_id` | `string` | — | Required. From `networking`'s `vpc_id` output. |
| `subnet_ids` | `list(string)` | — | Required, at least one. From `networking`'s subnet outputs. |
| `instance_profile_name` | `string` | — | Required. From `iam-role`'s `instance_profile_name` output. |
| `instance_type` | `string` | `"t3.micro"` | One of `t3.micro`, `t3.small`, `t3.medium`, `t3.large`. |
| `min_size` | `number` | `1` | Minimum instances the ASG will maintain. |
| `max_size` | `number` | `3` | Maximum instances the ASG will scale to. |
| `desired_capacity` | `number` | `1` | Target instance count. |
| `ingress_rules` | `list(object({...}))` | `[]` | See Network access above. SSH to `0.0.0.0/0` is rejected. |
| `user_data` | `string` | `""` | Startup script content, run once per instance launch. |
| `tags` | `map(string)` | `{}` | Additional tags, merged with the module's required tags. |

## Outputs

| Name | Description |
| --- | --- |
| `security_group_id` | This module's security group ID — reference it from another primitive (e.g. `rds`) needing to grant this workload ingress access. |
| `launch_template_id` | The launch template's ID, for operational tooling outside Terraform. |
| `autoscaling_group_name` | The ASG's name, for CloudWatch alarms, instance refreshes, or CI/CD triggers. |

## Composition

This shows how the module an be composed for use cases specific

```module "app_compute" {
  source = "../../modules/compute"

  team        = "platform"
  environment = "prod"
  purpose     = "api"

  vpc_id                 = module.networking.vpc_id
  subnet_ids              = module.networking.private_subnet_ids
  instance_profile_name    = module.app_role.instance_profile_name

  instance_type     = "t3.small"
  min_size          = 2
  max_size          = 4
  desired_capacity  = 2

  ingress_rules = [
    {
      description = "HTTP from internal load balancer"
      port        = 80
      source_security_group_id = module.lb_security_group.security_group_id
    }
  ]
}```

## Known limitations

- Egress is not restricted; all outbound traffic to `0.0.0.0/0` is
  permitted. Future will tell if the restrictions must be flexible.
- `instance_type` is limited to four approved sizes. Workloads requiring
  a larger instance are not currently supported without a module change.
- This module only provisions EC2.
- For the instnce_type, contact the platform team if an larger instance that is required.

However it is paramount to contact the platform engineering team when done using the instances. please never run 'terraform destroy'.
