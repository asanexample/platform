# Identity Center

Configures AWS IAM Identity Center (SSO) with permission sets, groups, users, and account assignments across the organization.

## Module

`infra/modules/aws/identity_center`

## Dependencies

- `organizations` — `../organizations`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `permission_sets` | `AdministratorAccess`, `ReadOnlyAccess`, `PowerUserAccess` | Session durations: 4h, 8h, 4h respectively |
| `groups` | `Admins`, `Developers`, `ReadOnly` | Maps to permission sets via account assignments |
| `users` | `josh` | Member of `Admins` group |
| `account_assignments` | 9 assignments | Admins get AdministratorAccess on all accounts; ReadOnly on all accounts; Developers get PowerUserAccess on Preprod only |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
