# `secure-data-bucket`

## Purpose

A COB primitive that provisions a single Amazon S3 bucket engineered to be
private, encrypted, versioned, and cost-managed by default. This document
describes the engineering reasoning behind every default this module
enforces — not as configuration options, but as properties of the
platform itself.

## Design principle

This module treats security and cost-control as properties of the
infrastructure, not as choices left to whoever happens to be calling it.
Every setting a consumer *cannot* change here was made non-configurable
deliberately: the strongest guarantee a shared platform primitive can
offer is that a category of mistake is structurally impossible, not
merely discouraged by a sensible default that someone can quietly
override under deadline pressure.

A related principle governs the inputs consumers *do* retain: a consumer
should only ever be asked to describe a fact about their data or their
requirements, never to supply an implementation detail they'd have to go
build or research elsewhere first. Where earlier designs asked for
something like a pre-existing encryption key, this module now asks a
plain question about sensitivity and derives the implementation itself.

## Data protection: versioning

Every bucket created by this module has S3 object versioning enabled,
unconditionally. There is no input controlling this.

**The mechanism:** once versioning is active, an upload to an existing
object key does not overwrite the prior object — it creates a new
version alongside it. A delete operation does not remove the object — it
places a delete marker on top of it, which makes the object disappear
from normal access while every version that existed before the delete
remains fully intact and recoverable.

**Why this cannot be a caller decision:** the single most common,
highest-consequence infrastructure failure mode is an irreversible
overwrite or delete — a deployment script that clobbers the wrong key, a
`PUT` retried against stale data, a manual delete run against the wrong
prefix. Making versioning optional means the platform's actual behavior
under a mistake depends on whether the specific team that provisioned
this specific bucket happened to think about that mistake in advance.
A shared platform should not depend on that. Versioning is therefore
treated as a fact about what a "secure data bucket" is, not a preference
about what one might be.

## Cost control: the baseline lifecycle schedule

Versioning has a direct, unavoidable cost consequence: every retained
version of every object is billed as a distinct object. Enabling
versioning without a corresponding retention policy converts a safety
feature into an unbounded, silently accumulating cost — the exact
failure mode this module is designed to prevent structurally, not by
instruction.

Every bucket this module creates carries one lifecycle rule, applied
unconditionally, encoding the following schedule:

| Trigger | Action | Engineering rationale |
|---|---|---|
| Object age reaches 60 days | Current version transitions to `STANDARD_IA` | Access frequency for most operational data (logs, application state, generated artifacts) drops sharply after the first month. `STANDARD_IA` preserves instant retrieval while reducing per-GB storage cost, at the price of a per-request retrieval fee — a correct tradeoff for data that is still occasionally read but no longer actively written to. |
| Object age reaches 180 days | Current version transitions to `GLACIER` | Data surviving six months without being deleted or superseded has demonstrated it is retained data, not working data. `GLACIER` accepts retrieval latency measured in minutes to hours in exchange for the lowest practical storage cost, which is the correct tradeoff once sub-second access is no longer a realistic requirement. |
| Object becomes a noncurrent version, plus 30 days | Noncurrent version transitions directly to `GLACIER` | Noncurrent versions exist purely as a recovery mechanism for versioning's protection guarantee, not as working data at any point in their lifetime. There is no scenario in which a noncurrent version needs `STANDARD` or `STANDARD_IA` performance, so it moves straight to the cheapest viable tier rather than staging through an intermediate class. |
| Object becomes a noncurrent version, plus 90 days | Noncurrent version is permanently deleted | Versioning's protection window is intentionally bounded, not infinite. Ninety days is sufficient to recover from an operational mistake discovered well after the fact, without converting every historical edit of every object into a permanent, compounding storage liability. |
| Multipart upload initiated but not completed, plus 7 days | Upload is aborted and its parts deleted | Incomplete multipart uploads are billed in full for every part already transferred, indefinitely, even though the object they belong to was never successfully created and is therefore inaccessible. This is a well-documented, frequently overlooked cost leak in S3-heavy workloads, and closing it requires no tradeoff — an incomplete upload has no operational value to preserve. |

**Why this cannot be a caller decision:** a retention schedule left to
individual discretion produces exactly the inconsistency this platform
exists to eliminate — some teams age data out promptly, others never
configure it at all and accumulate unbounded cost, and no two teams'
buckets behave predictably the same way under audit. Encoding the
schedule directly into the module converts "did this team remember to
configure lifecycle rules" into a question that no longer needs asking.

### The one lever consumers retain

Consumers may supply additional, narrowly-scoped **expiration** rules on
top of the baseline schedule, for data with a genuinely shorter required
lifetime than the default retention window — temporary upload staging
areas, short-lived processing intermediates, or data under a specific
compliance-driven deletion requirement shorter than 90 days.

```hcl
lifecycle_rules = [
  {
    id              = "expire-temp-uploads"
    prefix          = "tmp/"
    expiration_days = 7
  }
]
```

Consumers cannot configure transition timing, storage class selection, or
disable the baseline schedule. The baseline is not a starting point to be
overridden — it is the module's answer to "how should data in this
bucket age," and the only variance permitted is *shortening* a specific
prefix's total lifetime, never altering how it ages or extending it
beyond what the baseline already provides.

## Encryption

Every bucket is encrypted at rest, unconditionally. There is no
configuration path that produces an unencrypted bucket.

Rather than asking a consumer to choose an encryption *mechanism* — a
decision that requires knowing what SSE-S3 versus SSE-KMS even means, and
would otherwise require pre-creating a KMS key outside this module before
it could be used — the module asks a single question the consumer is
actually positioned to answer: how sensitive is the data going into this
bucket.

```hcl
variable "sensitivity" {
  type    = string
  default = "standard"
}
```

**`sensitivity = "standard"` (the default):** the bucket uses SSE-S3,
AWS's own fully-managed encryption key. No additional cost, no setup, and
adequate protection for the majority of operational data.

**`sensitivity = "high"`:** the module provisions a dedicated KMS key,
internally, and uses it to encrypt the bucket instead. This key is:

- **Created and owned by the module**, not supplied by the caller. A
  consumer never needs to have touched KMS directly, or have a key ready
  in advance, to use this option correctly.
- **Automatically rotated annually** (`enable_key_rotation = true`), a
  security decision the module makes on the consumer's behalf rather than
  something they would need to remember to configure themselves.
- **Protected by a 30-day deletion window** — AWS never deletes a KMS key
  immediately, since deleting a key still protecting live data makes that
  data permanently unrecoverable. Thirty days is the maximum window AWS
  allows, and the correct default for data important enough to warrant a
  dedicated key in the first place.
- **Given a human-readable alias**, so the key is identifiable in the AWS
  console by the bucket it protects, rather than by an opaque key ID.

Choosing `"high"` also changes what decrypting an object requires: a
principal now needs both an S3 permission (`s3:GetObject`) and a KMS
permission (`kms:Decrypt`) on this specific key — an independent second
gate that doesn't exist under `"standard"` — and every decrypt is recorded
in CloudTrail, producing an audit trail AWS-managed encryption does not
provide.

**Engineering rationale:** a consumer reasonably knows whether the data
they're storing is sensitive — customer PII, financial records, anything
under a compliance requirement. They are not reasonably expected to know
which AWS encryption mechanism satisfies that requirement, or to have
already built the supporting KMS infrastructure themselves. This module
absorbs that translation entirely.

## Public access

All four S3 public-access-block settings — `block_public_acls`,
`block_public_policy`, `ignore_public_acls`, `restrict_public_buckets` —
are enabled unconditionally, on every bucket, with no corresponding
input. A module whose defining characteristic is "secure" cannot expose
a mechanism for disabling the property that defines it. Public hosting
is a distinct use case requiring a distinct, explicitly-named module —
not a configuration path on this one.

## Identity and naming

S3 bucket names are unique across the entirety of AWS, not merely within
one account. A deliberate `team-environment-purpose` naming convention,
while readable, cannot on its own guarantee availability — the same name
may already be claimed by an entirely unrelated AWS customer. Every
bucket name this module produces is therefore composed of the
deliberate, readable identifier plus a randomly generated suffix,
guaranteeing successful creation without requiring a consumer to
discover an available name through trial and error.

## Access control boundary

This module owns storage and its security posture. It does not own
access control. Read and write access should be granted through IAM
policy attachments referencing this module's `bucket_arn` output,
composed via the `iam-role` primitive — not through this module
directly.

`allowed_principal_arns` exists as a narrow, deliberate exception for
access patterns IAM role composition cannot express: cross-account
grants, or AWS service principals (CloudTrail, ELB access log delivery)
that require a bucket policy specifically rather than an IAM policy.
Consumers should default to IAM composition and treat this input as the
exception, not the first option reached for.

## Known limitations

- **`allowed_principal_arns` does not currently validate its contents.**
  The module does not block a wildcard (`"*"`) or otherwise overly broad
  principal from being supplied, which — if used carelessly — can grant
  effectively public access via bucket policy independently of the
  public-access-block settings enforced elsewhere in this module.
  Consumers using this input are responsible for scoping principals
  precisely. Tightening this with explicit validation is a known,
  tracked improvement, not yet implemented.
- The baseline lifecycle schedule applies uniformly across the entire
  bucket. Consumers requiring different transition timing for different
  data types within the same bucket should provision separate buckets
  per data type rather than relying on prefix-scoped transition
  overrides, which this module does not expose.
- Cross-region replication is not currently provisioned by this module.
  Buckets requiring geographic redundancy beyond S3's native durability
  guarantees are not yet supported.
- **KMS key policy is currently minimal.** When `sensitivity = "high"`, this module
  creates a dedicated KMS key with a policy granting root-account access (required
  by AWS to avoid permanent lockout) and S3 service access (required for SSE-KMS to
  function). It does **not** currently expose a way for consuming teams to grant
  additional principals (e.g. specific IAM roles) access to decrypt/encrypt with the
  key. Teams needing broader access to a high-sensitivity bucket's key should manage
  this via a follow-up KMS policy change, or flag it to the platform team for the
  module to support via a future `kms_key_additional_principals` variable.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `team` | `string` | — | Owning team. Lowercase letters, numbers, hyphens, 2-20 characters. |
| `environment` | `string` | — | One of `dev`, `staging`, `prod`. |
| `purpose` | `string` | — | Short, name-safe identifier. Feeds the bucket name; longer context belongs in `description`. |
| `description` | `string` | `""` | Human-readable context, stored as a tag. |
| `sensitivity` | `string` | `"standard"` | `"standard"` or `"high"`. See Encryption above. |
| `lifecycle_rules` | `list(object({ id = string, prefix = optional(string, ""), expiration_days = number }))` | `[]` | Additional early-expiration rules, layered on top of the baseline schedule described above. |
| `allowed_principal_arns` | `list(string)` | `[]` | Principals granted access via bucket policy. See access control boundary and known limitations above. |
| `tags` | `map(string)` | `{}` | Additional tags, merged with the module's required tags. |

## Outputs

| Name | Description |
|---|---|
| `bucket_id` | Bucket name/ID. |
| `bucket_arn` | Full ARN. Used to scope `iam-role` policies to this bucket. |
| `bucket_domain_name` | Bucket domain name, for references outside Terraform. |
| `kms_key_arn` | The KMS key created for this bucket if `sensitivity = "high"`, or `null` otherwise. Used to scope `kms:Decrypt` grants in downstream IAM policies. |

## Composition

```hcl
module "customer_pii_bucket" {
  source = "../../modules/secure-data-bucket"

  team        = "data"
  environment = "prod"
  purpose     = "customer-pii"
  description = "Customer PII requiring audit-logged access."

  sensitivity = "high"
}

module "app_logs_bucket" {
  source = "../../modules/secure-data-bucket"

  team        = "platform"
  environment = "prod"
  purpose     = "app-logs"
  description = "Application logs from the prod API service."

  lifecycle_rules = [
    {
      id              = "expire-temp-debug-dumps"
      prefix          = "debug/"
      expiration_days = 14
    }
  ]
}

data "aws_iam_policy_document" "pii_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "kms:Decrypt"]
    resources = [
      "${module.customer_pii_bucket.bucket_arn}/*",
      module.customer_pii_bucket.kms_key_arn
    ]
  }
}

module "data_service_role" {
  source = "../../modules/iam-role"

  team        = "data"
  environment = "prod"
  purpose     = "pii-service"

  inline_policies = {
    "pii-access" = data.aws_iam_policy_document.pii_access.json
  }
}
```