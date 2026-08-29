# Module overview

Object Storage (secure-data-bucket) is a COB internal infrastructure that provisions a single S3 bucket configured to be private and encrypted by default.
This module's whole reason for existing is owning a specific security posture like versioning, encryption, and public-access blocking. Consumers get to influence shape (naming identity, lifecycle/retention rules, who else besides the bucket's own IAM-granted principals may access it) but never security fundamentals.

## What this module owns, and what it doesn't

This module is responsible for storage and its security posture: bucket creation, encryption, versioning, lifecycle rules, and blocking public access unconditionally.

It does not own who is allowed to access this bucket. That's `iam-role`'s job: access should flow through IAM policy attachments referencing this bucket's ARN, not through this module.

## Opinionated defaults — what you can't configure, and why

| Behavior | Value | Why it's fixed |
| --- | --- | --- |
| Public access | Always fully blocked (all 4 settings) | To enforce Beejan's Technologies Standards |
| Encryption at rest | Always on | Only the key varies (AWS-managed vs. customer KMS key) — there is no code path that produces an unencrypted bucket. |
| Bucket naming | Consumer can't fully control it | S3 bucket names must be globally unique across every AWS account, not just yours. The module appends a random suffix to a deliberate `team-environment-description` name so uniqueness is guaranteed without you needing to search for an available name. |

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `team` | `string` | — | Team that owns this bucket. Lowercase letters, 2-20 characters. |
| `environment` | `string` | — | `dev`, or `prod`. |
| `description` | `string` | — | Short, name-safe that describes (e.g. `app-logs`, `user-uploads`). Feeds into the bucket name, so keep it short, put longer context in `description` instead. |
| `description` | `string` | `""` | Optional longer human-readable description, stored as a tag, not in the name. |
| `versioning_enabled` | `bool` | `true` | Whether to enable object versioning. Defaults on, this is what protects against accidental overwrites/deletes. |
| `kms_key_arn` | `string` | `null` | Optional customer-managed KMS key ARN. Omit to use AWS-managed SSE-S3 encryption instead. |
| `lifecycle_rules` | `list(object({...}))` | `[]` | Expiration and storage-class transition rules. See structure below. |
| `allowed_principal_arns` | `list(string)` | `[]` | Principal ARNs granted access via bucket policy, beyond what IAM role policies already provide. Use sparingly — see ownership note above. |
| `tags` | `map(string)` | `{}` | Additional tags merged with the module's own required tags. |

### `lifecycle_rules` structure

\```hcl
lifecycle_rules = [
  {
    id                       = "expire-old-logs"
    prefix                   = "logs/"
    expiration_days          = 90
  },
  {
    id                       = "archive-after-30-days"
    prefix                   = "archives/"
    transition_days          = 30
    transition_storage_class = "GLACIER"
  }
]
\```

Only `id` is required `enabled` defaults to `true`, `prefix` defaults to `""` (applies to the whole bucket), and `expiration_days`/`transition_days` are omitted entirely if that behavior isn't needed for a given rule.

## Outputs

| Name | Description |
| --- | --- |
| `bucket_id` | The bucket's name/ID. |
| `bucket_arn` | Full ARN — pass this into `iam-role`'s `inline_policies` to scope a policy to this specific bucket. |
| `bucket_domain_name` | The bucket's domain name, if needed for referencing it outside Terraform |
| `kms_key_arn` | Echoes back the KMS key in use (or `null` if using AWS-managed encryption), so downstream IAM policies can grant `kms:Decrypt` where needed. |

## How to compose it

\```hcl
module "app_logs_bucket" {
  source = "../../modules/secure-data-bucket"

  team        = "platform"
  environment = "prod"
  purpose     = "app-logs"
  description = "Application logs from the prod API service, retained 90 days then expired."

  lifecycle_rules = [
    {
      id               = "expire-after-90-days"
      expiration_days  = 90
    }
  ]
}
\```

### Granting access — the normal path, through `iam-role`

This is how most teams should grant access to a bucket created by this module — through IAM, not through `allowed_principal_arns`:

\```hcl
data "aws_iam_policy_document" "app_logs_access" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject"]

    resources = [
      "${module.app_logs_bucket.bucket_arn}/*"
    ]
  }
}

module "app_role" {
  source = "../../modules/iam-role"

  team        = "platform"
  environment = "prod"
  purpose     = "app-service"

  inline_policies = {
    "app-logs-access" = data.aws_iam_policy_document.app_logs_access.json
  }
}
\```

### Granting access — the exception path, via bucket policy

Only reach for `allowed_principal_arns` when IAM policy attachment genuinely isn't an option — for example, an AWS service principal delivering logs:

\```hcl
module "elb_logs_bucket" {
  source = "../../modules/secure-data-bucket"

  team        = "platform"
  environment = "prod"
  purpose     = "elb-access-logs"

  allowed_principal_arns = [
    "arn:aws:iam::127311923021:root"  # AWS's ELB log-delivery account for this region
  ]
}
\```

### Using a customer-managed KMS key

\```hcl
module "sensitive_data_bucket" {
  source = "../../modules/secure-data-bucket"

  team        = "data"
  environment = "prod"
  purpose     = "customer-pii"

  kms_key_arn = aws_kms_key.data_team_key.arn
}
\```

Omit `kms_key_arn` entirely for buckets that don't need the additional key-policy control or CloudTrail audit trail a customer-managed key provides — AWS-managed SSE-S3 encryption applies automatically either way.

## What you'll need to build next

This module gives you secure storage only. Depending on your use case, you may also need:

- An `iam-role` granting the right principals `s3:GetObject`/`s3:PutObject` scoped to this bucket's `bucket_arn`
- A VPC endpoint for S3, if resources in a private subnet (via `networking`) need to reach this bucket without traversing a NAT gateway

## Walking through the Design Lenses

### Encapsulation

The module exposes identity (team/environment/purpose), a small set of real tradeoffs (versioning_enabled, lifecycle_rules, kms_key_arn), and an escape hatch for external access (allowed_principal_arns). It hides the actual bucket-naming/uniqueness mechanism, the encryption resource wiring, and the public-access-block resource entirely.

### Privilege

For priviledge, aws_s3_bucket_public_access_block is hardcoded. Allowed_principal_arns is the one real privilege-relevant input left, and it's scoped narrowly (specific S3 actions, specific bucket ARN only) rather than granting broad access.

### Volatility

lifecycle_rules is the highest-volatility input here (every team's retention needs differ, genuinely business-driven), so it's a fully flexible structural type. versioning_enabled and kms_key_arn are medium volatility — set once per bucket, rarely revisited. Encryption-on and public-access-blocked are zero volatility by design meaning that they should never change, so they're not inputs at all, just hardcoded facts about what this module produces.

### Abstraction

The module absorbs the complexity behind a small, clear interface. A Consumer just gets a bucket that's private.
