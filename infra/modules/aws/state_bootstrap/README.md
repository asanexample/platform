# State Bootstrap

Creates the S3 bucket and DynamoDB table required for OpenTofu/Terraform remote state storage and locking. The S3 bucket is configured with versioning enabled, KMS server-side encryption with bucket key, and all public access blocked. The DynamoDB table uses PAY_PER_REQUEST billing and a `LockID` hash key for state locking.

## Usage

```hcl
module "state_bootstrap" {
  source = "../../modules/aws/state_bootstrap"

  bucket_name         = "centric-platform-tfstate"
  dynamodb_table_name = "terraform-locks"

  tags = {
    ManagedBy = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "state_bootstrap" {
  source = "../../modules/aws/state_bootstrap"
  create = false

  bucket_name = "unused"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_dynamodb_table.locks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bucket_name"></a> [bucket\_name](#input\_bucket\_name) | Name of the S3 bucket for Terraform state. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the state storage resources. | `bool` | `true` | no |
| <a name="input_dynamodb_table_name"></a> [dynamodb\_table\_name](#input\_dynamodb\_table\_name) | Name of the DynamoDB table for state locking. | `string` | `"terraform-locks"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the S3 state bucket. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the S3 state bucket. |
| <a name="output_dynamodb_table_arn"></a> [dynamodb\_table\_arn](#output\_dynamodb\_table\_arn) | ARN of the DynamoDB lock table. |
| <a name="output_dynamodb_table_name"></a> [dynamodb\_table\_name](#output\_dynamodb\_table\_name) | Name of the DynamoDB lock table. |
<!-- END_TF_DOCS -->

## Notes

- This module is typically run once in the management account to bootstrap state storage before any other infrastructure is deployed.
- The DynamoDB table name defaults to `terraform-locks` if not specified.
- State bucket versioning ensures that prior state versions are recoverable.
- Access to the state bucket is controlled via the `TerraformStateAccess` IAM role defined in the management account, not by this module.

## Related ADRs

- ADR-002: AWS State Storage in S3 with Cloud-Aware Routing
- ADR-006: State Bootstrap Pattern
