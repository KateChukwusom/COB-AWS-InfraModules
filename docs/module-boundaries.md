# Module Design Principles

Every module in COB is designed around three independent questions,
applied deliberately rather than left to convention:

## Encapsulation

What belongs inside a module's boundary? A module should group only
the resources that are always created, changed, and destroyed together
for one coherent purpose, not a single AWS resource wrapped in another
interface, and not an unrelated bundle of resources that happen to be
used together once. Each COB module represents one real infrastructure
capability. (e.g. "secure object storage," not just "an S3 bucket").

## Volatility

How often does a value or resource change, and how much does it vary
across environments or teams? High-volatility resources (compute
workloads, container images) are isolated into their own modules so
their frequent churn never creates risk for stable infrastructure.
Low-volatility resources (networking, IAM, databases) are kept in
tightly scoped, infrequently-changed modules specifically to protect
them from unnecessary churn.

## Privilege

How much damage is possible if a resource is misconfigured or misused?
High-privilege capabilities (networking, IAM, databases) restrict who
can modify them and constrain which variables are exposed at all,
security-critical defaults are hardcoded rather than left as toggles.
Low-privilege values (tags, naming) are freely exposed as variables
with no additional guardrails.

Every module's `README.md` documents its own Encapsulation, Volatility,
and Privilege classification, along with the reasoning behind its
specific inputs and outputs.

