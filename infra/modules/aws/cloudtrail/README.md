# CloudTrail

Creates an AWS CloudTrail trail with an encrypted S3 bucket for log storage, optional CloudWatch Logs integration, and Secrets Manager activity alarms. The S3 bucket is configured with versioning, KMS encryption, public access blocking, and lifecycle policies for log retention. When CloudWatch is enabled, the module creates a log group with a dedicated IAM role for CloudTrail delivery, and can optionally deploy metric filters and alarms to detect Secrets Manager write activity.

## Usage

```hcl
module "cloudtrail" {
  source = "../../modules/aws/cloudtrail"

  trail_name         = "platform-use1-audit"
  is_multi_region    = true
  log_retention_days = 90
  enable_cloudwatch  = true

  data_event_selectors = [
    {
      name          = "secrets-manager"
      resource_type = "AWS::SecretsManager::Secret"
      resource_arns = []
    }
  ]

  enable_secrets_alarms = true

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "cloudtrail" {
  source = "../../modules/aws/cloudtrail"
  create = false

  trail_name = "unused"
}
```

### Minimal Single-Region Trail

```hcl
module "cloudtrail" {
  source = "../../modules/aws/cloudtrail"

  trail_name        = "preprod-use1-audit"
  is_multi_region   = false
  enable_cloudwatch = false

  tags = {
    Environment = "preprod"
  }
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
| [aws_cloudtrail.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) | resource |
| [aws_cloudwatch_log_group.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_metric_filter.secrets_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_metric_alarm.secrets_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.cloudtrail_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cloudtrail_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.trail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.trail_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_trail_name"></a> [trail\_name](#input\_trail\_name) | Name of the CloudTrail trail | `string` | n/a | yes |
| <a name="input_cloudwatch_retention_days"></a> [cloudwatch\_retention\_days](#input\_cloudwatch\_retention\_days) | CloudWatch log group retention in days | `number` | `30` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources should be created | `bool` | `true` | no |
| <a name="input_data_event_selectors"></a> [data\_event\_selectors](#input\_data\_event\_selectors) | Advanced event selectors for data events | <pre>list(object({<br/>    name          = string<br/>    resource_type = string<br/>    resource_arns = optional(list(string), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_enable_cloudwatch"></a> [enable\_cloudwatch](#input\_enable\_cloudwatch) | Send CloudTrail events to CloudWatch Logs for metric filters and alarms | `bool` | `true` | no |
| <a name="input_enable_secrets_alarms"></a> [enable\_secrets\_alarms](#input\_enable\_secrets\_alarms) | Create CloudWatch metric filters and alarms for Secrets Manager activity | `bool` | `false` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow S3 bucket to be destroyed even if it contains objects | `bool` | `false` | no |
| <a name="input_is_multi_region"></a> [is\_multi\_region](#input\_is\_multi\_region) | Whether the trail captures events from all regions | `bool` | `false` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain CloudTrail logs in S3 | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group for CloudTrail events |
| <a name="output_s3_bucket_id"></a> [s3\_bucket\_id](#output\_s3\_bucket\_id) | ID of the S3 bucket storing CloudTrail logs |
| <a name="output_trail_arn"></a> [trail\_arn](#output\_trail\_arn) | ARN of the CloudTrail trail |
<!-- END_TF_DOCS -->

## Notes

- The S3 bucket uses KMS encryption (`aws:kms`) with bucket key enabled, and blocks all public access.
- Log file validation is always enabled on the trail.
- The Secrets Manager alarm triggers on any `GetSecretValue`, `PutSecretValue`, `CreateSecret`, or `DeleteSecret` event within a 5-minute window.
- Set `force_destroy = true` if you need to tear down the bucket with logs still in it (e.g., in non-production environments).
