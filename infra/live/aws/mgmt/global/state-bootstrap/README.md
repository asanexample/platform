# State Bootstrap

Creates the S3 bucket and DynamoDB table used as the Terraform/OpenTofu remote state backend for all environments.

## Module

`infra/modules/aws/state_bootstrap`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `bucket_name` | `tfstate-mgmt-<MGMT_ACCOUNT_ID>` | S3 bucket for state files |
| `dynamodb_table_name` | `terraform-locks` | DynamoDB table for state locking |

**Note:** This unit uses a `local` backend override (state stored in `terraform.tfstate` on disk). This is intentional -- it creates the S3 bucket that all other units store state in, so it cannot use that bucket itself.

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
