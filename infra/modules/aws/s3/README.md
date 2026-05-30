# S3

Creates private, SSE-S3-encrypted S3 buckets with all public access blocked and
`BucketOwnerEnforced` ownership (ACLs disabled — access is policy-only). Optionally attaches a **bucket
policy scoped to specific reader/writer IAM role ARNs**, used for least-privilege **cross-account**
access (tighter than an account `:root` grant).

Cross-account S3 access from an IAM role requires grants on **both** ends: this bucket policy **and** the
caller's own identity policy (granted on the team role via the `iam_roles` module). Used to give a
tenant's EKS Pod Identity role read access to a shared dataset in another account (see ADR-041).

The module is team-agnostic: the per-bucket `reader_role_arns` are assembled at the terragrunt unit from
`teams.hcl`.

## Usage

```hcl
module "s3" {
  source = "../../modules/aws/s3"

  buckets = {
    "asanexample-team-alpha-data" = {
      # Cross-account: the preprod team Pod Identity role gets read access.
      reader_role_arns = ["arn:aws:iam::620830101009:role/Pod-team-alpha"]
      tags             = { Team = "alpha" }
    }
  }
  tags = { Environment = "platform" }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_buckets"></a> [buckets](#input\_buckets) | Map of bucket name -> config. Each bucket is private (all public access blocked) and SSE-S3<br/>encrypted. reader\_role\_arns / writer\_role\_arns are granted via a bucket policy scoped to those exact<br/>role ARNs (least-privilege cross-account: tighter than an account :root grant). Cross-account S3<br/>access additionally requires the caller's own identity policy to allow it (granted on the team role). | <pre>map(object({<br/>    reader_role_arns = optional(list(string), [])<br/>    writer_role_arns = optional(list(string), [])<br/>    tags             = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to all buckets | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arns"></a> [bucket\_arns](#output\_bucket\_arns) | Map of bucket name -> ARN |
| <a name="output_bucket_ids"></a> [bucket\_ids](#output\_bucket\_ids) | Map of bucket name -> ID (name) |
<!-- END_TF_DOCS -->
