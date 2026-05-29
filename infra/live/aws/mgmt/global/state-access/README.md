# State Access

Creates the `TerraformStateAccess` IAM role in the management account, allowing cross-account access to the S3 state bucket and DynamoDB lock table.

## Module

`infra/modules/aws/iam_roles`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `roles` | `TerraformStateAccess` | Single role with 1h max session duration |
| Trust principals | Platform (`<PLATFORM_ACCOUNT_ID>`), Management (`<MGMT_ACCOUNT_ID>`), PreProd (`<PREPROD_ACCOUNT_ID>`) | Cross-account assume-role |
| S3 access | `tfstate-mgmt-<MGMT_ACCOUNT_ID>` | GetObject, PutObject, DeleteObject, ListBucket |
| DynamoDB access | `terraform-locks` (us-east-1) | GetItem, PutItem, DeleteItem |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
