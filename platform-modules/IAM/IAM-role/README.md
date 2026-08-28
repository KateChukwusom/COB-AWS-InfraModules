# iam-role

A reusable, least-privilege IAM role primitive for Beejan Technologies' COB
platform. Any team — networking, compute, storage, data-eng, or otherwise —
calls this module to create a role, without writing raw IAM policy JSON or
deciding IAM security posture themselves.

## Prerequisite — read this before your first `terraform apply`

This module does **not** create its own permissions boundary policies. It
looks up two pre-existing IAM policies by name:

- `platform-boundary-read-only`
- `platform-boundary-read-write`

These must already exist in your AWS account before this module can be
used at all — created once, separately, by whoever owns IAM security
(ideally its own small `platform-boundaries` module, not this one). If
they don't exist yet, every call to this module fails at `plan` time,
because the two `data "aws_iam_policy"` lookups in `main.tf` have nothing
to find.

**Why this module doesn't create them itself:** an earlier version did —
each call to `iam-role` created its own boundary policy, named only from
`team` and `access_level` (e.g. `boundary-storage-read-only`). That works
the first time a team calls the module. It breaks the moment the *same*
team calls it a second time for a *different* role, because both calls try
to create an IAM policy under the identical name — AWS either rejects the
second one outright, or silently produces inconsistent content under a
name that's supposed to be one stable thing. Boundary policies are a
**shared singleton** — there should be exactly one "read-only ceiling" for
the whole platform, not one freshly minted per role. So they're created
once, externally, and every role this module creates just references that
one shared ceiling by reading it, never creating it.

## What this module decides for you (you can't change these)

- **Every role gets a permissions boundary — no exceptions.** There is no
  variable to skip this. `permissions_boundary` on the role is wired
  directly to a computed lookup, never to a nullable input — even if
  someone later attaches a broader policy to the role by mistake, the
  boundary caps what can actually be exercised.
- **Every action granted is explicitly named.** No wildcards like
  `s3:Get*` for either tier — every permission is individually listed in
  the module's internal lookup table, so nothing broader than intended
  ever slips through.
- **The role name and tags are computed, not typed.** You supply the raw
  ingredients (`team`, `app_name`, `environment`); the module builds the
  name from a fixed formula, so every role at the company is consistently
  named and traceable back to an owner without anyone needing to remember
  a naming convention by hand.

## What you decide

| Variable | Type | Why this type |
|---|---|---|
| `team` | free-form (pattern-constrained) | the set of valid teams grows over time — can't be pre-approved as an enum |
| `app_name` | free-form (pattern-constrained) | same reasoning as `team` |
| `environment` | enum: `dev` / `staging` / `prod` | fixed, small, known set that won't grow next week |
| `trusted_principal` | enum: pre-approved AWS service principals | answers "who can assume the role" — the single most dangerous field to leave open, so it's a closed list |
| `access_level` | enum: `read-only` / `read-write` | describes the *shape* of access, deliberately separate from *what* it applies to |
| `resource_service` | enum: `s3` / `dynamodb` / `rds` / `glue` | tells the module which row of its internal actions lookup to use |
| `resource_arns` | free-form list | genuinely varies per consumer — this is what makes the module reusable rather than tied to one team's specific resources |

## Why `access_level` and `resource_service` / `resource_arns` are kept separate

`access_level` answers "how much" (read vs. write). `resource_service` and
`resource_arns` answer "of what, and where." Keeping these as separate
inputs is the biggest reason this module works for every team without
being rewritten: the networking team, the storage team, and a Lambda
function can all request `read-write`, and each just points it at their
own resources. Adding support for a new AWS service later means adding one
new entry to the internal lookup table — the interface you call never has
to change.

## How the internal actions lookup works

Inside `main.tf`, `actions_lookup` is a **nested** map — `[service][access_level]`
— not a flat map with combined string keys. This was a deliberate choice
made after testing the flat alternative:

```hcl
# What we use — nested, two clean dimensions:
actions_lookup = {
  s3 = {
    "read-only"  = [...]
    "read-write" = [...]
  }
  dynamodb = { ... }
}

# What we tried and rejected — flat, combined-string keys:
# action_sets = {
#   "s3-read"  = [...]   # doesn't match the access_level enum ("read-only")
#   "s3-write" = [...]   # doesn't match either ("read-write")
# }
```

The flat version broke because its keys (`"s3-read"`, `"s3-write"`) didn't
match the actual `access_level` enum values (`"read-only"`, `"read-write"`)
— a lookup built by concatenating the two variables would have searched
for `"s3-read-write"`, which didn't exist in the map at all. That's a
structural risk of flat, string-concatenated keys: they require two
separate pieces of code (the enum's exact wording and the map's key
naming) to stay in sync by hand. The nested version avoids this entirely
— it takes `resource_service` and `access_level` as two independent,
already-validated keys, so there's no string to keep in sync, and the
shape of the map visually documents that there are two real dimensions
here, not one.

`granted_actions = local.actions_lookup[var.resource_service][var.access_level]`
is the actual two-key lookup — both keys already validated as enums back
in `variables.tf`, so this line can never fail on a value it doesn't
recognize.

## Why `admin-scoped` isn't offered

An earlier version of this module included a third tier, `admin-scoped`,
granting full wildcard access to a service, gated behind a cross-variable
validation that blocked it outside `prod` unless explicitly overridden. It
was removed to keep this version's blast radius smaller and more
predictable: `read-write` already covers the large majority of real
workload needs. A tier granting full service-wide access is a high-stakes
decision that deserves its own separate, more heavily reviewed path — not
a checkbox living inside a general-purpose primitive that any team can
reach for casually.

## How the permissions boundary is actually attached

Four pieces, working together:

1. **The policies exist already** (see Prerequisite above) — `platform-boundary-read-only` and `platform-boundary-read-write`, created once, externally.
2. **This module looks them up** via `data "aws_iam_policy"` blocks — read-only, never creates them.
3. **A lookup map picks the right one** — `boundary_policy_arn_map[var.access_level]` — using the same already-validated `access_level` enum.
4. **The role's built-in `permissions_boundary` argument is wired directly to that lookup** — no variable, no null path. Every role this module creates has a boundary from the moment it's created, and which boundary applies is always computed the same predictable way.

## Why the permission policy is inline, not a separate managed policy + attachment

```hcl
resource "aws_iam_role_policy" "this" {
  name   = "${local.role_name}-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}
```

This single resource both creates and attaches the policy — there's no
separate `aws_iam_role_policy_attachment` resource, and that's deliberate,
not an oversight. The alternative pattern (a standalone `aws_iam_policy` +
a separate attachment resource) exists for policies meant to be reused
across multiple roles. This module's permission policy is the opposite
case: it's computed fresh from `resource_arns` and `access_level` every
single call, unique to that one role, never meant to be shared with any
other role. Since it's a strict one-to-one relationship, the inline
pattern is the more correct fit — it avoids creating an orphaned,
independent policy object in IAM with no real reason to exist on its own.

The boundary policies, by contrast, genuinely *are* shared across every
role at a given tier — which is exactly why those use the read-only
`data` lookup pattern instead, described above. Same module, two
different attachment mechanisms, each matched to whether the policy is
one-to-one or shared.

## Example — Lambda needs get/put on an S3 bucket

```hcl
module "lambda_bucket_access_role" {
  source = "../iam-role"

  team              = "data-eng"
  app_name          = "ingestion-lambda"
  environment       = "prod"
  trusted_principal = "lambda.amazonaws.com"
  access_level      = "read-write"
  resource_service  = "s3"
  resource_arns     = [module.landing_zone_bucket.bucket_arn]
}

resource "aws_lambda_function" "ingestion" {
  function_name = "ingestion-lambda"
  role          = module.lambda_bucket_access_role.role_arn
  # ...
}
```

`resource_arns` references another module's *output*
(`module.landing_zone_bucket.bucket_arn`), not a hand-typed ARN. If the
bucket is ever recreated under a new name, this role's policy updates
automatically on the next `terraform apply` — nothing to remember to fix
by hand.

## Example — same module, completely different team and service

```hcl
module "networking_health_check_role" {
  source = "../iam-role"

  team              = "networking"
  app_name          = "nat-health-check"
  environment       = "prod"
  trusted_principal = "ec2.amazonaws.com"
  access_level      = "read-write"
  resource_service  = "dynamodb"
  resource_arns     = ["arn:aws:dynamodb:us-east-1:111111111111:table/nat-health-state"]
}
```

Zero changes to the module between these two examples — only the values
passed in. That's the actual test of a genuine platform primitive: could a
team you didn't specifically design for use it, unmodified, for a purpose
you didn't anticipate? Both examples pass.

## Outputs

| Output | Use |
|---|---|
| `role_arn` | pass into `role`, `execution_role_arn`, or an instance profile |
| `role_name` | debugging, logging, or CloudWatch alarm references |

Only the ARN and name are exposed — never the policy documents or internal
lookup tables. Consumers attach an *identity*; they never need to know,
and never get told, exactly what that identity can do internally.

## What this module does *not* protect against

- **A consumer requesting `read-write` when `read-only` would do.** The
  module can't read intent — it can only enforce that whatever tier is
  requested doesn't exceed what that tier is defined to grant. Treat
  `access_level = "read-write"` requests in code review the same way
  you'd question any other privilege increase.
- **Someone bypassing this module and writing a raw `aws_iam_role`
  resource directly.** Nothing in Terraform stops that. The backstop is
  outside this module — company-wide policy-as-code scanning (OPA,
  Sentinel, or Checkov run against every `terraform plan`) that
  independently flags any IAM role, from any source, lacking a
  permissions boundary or granting an unreviewed wildcard.
- **The two boundary policies drifting or being deleted.** Since this
  module only references them, their content is governed elsewhere. If
  they're loosened, every role this module creates inherits that change
  automatically on its next apply — powerful, but it means their owner
  carries real responsibility for keeping them correct.


## Putting the whole flow together

Someone calls the module with `access_level = "read-write"`, `variables.tf` already confirmed that's a valid value. boundary_policy_arn_map["read-write"] resolves to data.
aws_iam_policy.boundary_read_write.arn, the real ARN of the pre-existing platform-boundary-read-write policy in AWS.
That ARN gets wired straight into aws_iam_role.COB_iam_role's permissions_boundary argument.
The role is created with that boundary attached, permanently.