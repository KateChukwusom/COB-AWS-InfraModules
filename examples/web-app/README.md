# Example: Simple Web App

## Scenario

The Internal Tools team needs a basic environment to run a web app:
a network to sit in, a server to run it on, and a bucket for file
uploads.

Instead of provisioning a VPC, an EC2 instance, and an S3 bucket by
hand, this example shows how the same result comes from composing
three COB modules.

## What this demonstrates

| COB module | Role here |
| --- | --- |
| `networking` | Provides the VPC and subnet the EC2 instance runs in. |
| `storage` | Provides a secure, encrypted S3 bucket for uploads. |
| `compute-ec2` | Runs the web app, placed into the VPC created above. |

Note that `compute-ec2` doesn't create its own network — it takes
`vpc_id` and `subnet_ids` directly from `networking`'s outputs. That's
the composition: one module's output becomes another module's input.

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

- `vpc_id` — the created network
- `uploads_bucket` — where the app stores uploaded files
- `ec2_instance_id` — the running web app server
