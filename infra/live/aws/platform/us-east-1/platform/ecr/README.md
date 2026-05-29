# ECR

Creates ECR repositories for tenant application container images in the platform account.

## Module

`infra/modules/aws/ecr`

## Dependencies

None.

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `repositories` | `team-alpha/demo`, `team-bravo/demo` | One repo per team/app combination |
| `pull_account_ids` | `<PREPROD_ACCOUNT_ID>`, `<PROD_ACCOUNT_ID>` | Grants cross-account pull access to preprod and prod |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
