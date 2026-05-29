# Identity Center

Configures AWS IAM Identity Center (SSO) with permission sets, groups, users, and account assignments across the organization.

## Module

`infra/modules/aws/identity_center`

## Dependencies

- `organizations` — `../organizations`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `permission_sets` | `AdministratorAccess`, `ReadOnlyAccess`, `PowerUserAccess`, and one `Dev-<team>` per team | Session durations: 4h, 8h, 4h, 4h. Each `Dev-<team>` grants account-wide read + assume-role into that team's `DeveloperAccess-<team>` (ADR-039) |
| `groups` | `Admins`, `ReadOnly`, and one `Developers-<team>` per team | Maps to permission sets via account assignments |
| `users` | `josh` | Member of `Admins` group |
| `account_assignments` | Admins/ReadOnly on all accounts; each `Developers-<team>` gets its `Dev-<team>` set on Preprod | The former broad `Developers → PowerUserAccess` assignment was removed (it bypassed namespace RBAC) |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
