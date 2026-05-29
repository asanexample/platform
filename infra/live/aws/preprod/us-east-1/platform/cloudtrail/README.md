# cloudtrail

Deploys a CloudTrail trail for secrets audit logging in the preprod account with CloudWatch integration and alarms.

## Module

`infra/modules/aws/cloudtrail`

## Dependencies

None

## Key Inputs

| Input                   | Value                        | Notes                                   |
|-------------------------|------------------------------|-----------------------------------------|
| `trail_name`            | `preprod-use1-secrets-audit` | Derived from env and region             |
| `enable_cloudwatch`     | `true`                       | Streams trail events to CloudWatch Logs |
| `enable_secrets_alarms` | `true`                       | Alerts on secrets access                |
| `log_retention_days`    | `90`                         |                                         |
| `data_event_selectors`  | `[]`                         | No data events configured yet           |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
