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
| Trust principals | Platform (`829808296602`), Management (`851725353202`), PreProd (`620830101009`) | Cross-account assume-role |
| S3 access | `tfstate-mgmt-851725353202` | GetObject, PutObject, DeleteObject, ListBucket |
| DynamoDB access | `terraform-locks` (us-east-1) | GetItem, PutItem, DeleteItem |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
