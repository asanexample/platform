# Organizations

Creates the AWS Organization, organizational units, member accounts, and service control policies (SCPs).

## Module

`infra/modules/aws/organizations`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `allowed_regions` | `us-east-1`, `us-west-2` | SCP-enforced region restriction |
| `required_tags` | `Environment`, `ManagedBy`, `Owner` | SCP-enforced tagging policy |
| `exempt_roles` | `OrganizationAccountAccessRole`, `github-actions-terratest`, `PlatformDeployer` | Roles exempt from SCPs |
| `organizational_units` | `Platform`, `Workloads`, `Workloads/Preprod`, `Workloads/Prod`, `Workloads/Regulated` | Nested OU hierarchy |
| `accounts` | `Platform`, `Test`, `Preprod`, `Prod` | Placed into their respective OUs |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
