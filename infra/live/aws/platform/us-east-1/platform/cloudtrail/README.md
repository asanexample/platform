# CloudTrail

Deploys a CloudTrail trail for secrets audit logging with CloudWatch alarms.

## Module

`infra/modules/aws/cloudtrail`

## Dependencies

None.

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `trail_name` | `platform-use1-secrets-audit` | Naming follows `{env}-{region_abbv}-secrets-audit` |
| `enable_cloudwatch` | `true` | Streams trail events to CloudWatch Logs |
| `enable_secrets_alarms` | `true` | CloudWatch alarms for secrets access events |
| `log_retention_days` | `90` | |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
