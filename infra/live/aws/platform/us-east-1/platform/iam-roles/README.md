# IAM Roles

Creates purpose-built IAM roles for platform operations in the platform account (829808296602).

## Module

`infra/modules/aws/iam_roles`

## Dependencies

None.

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `roles.PlatformAdmin` | EKS, SSM, Secrets Manager read | Trusted by management + platform SSO AdministratorAccess roles; 4-hour sessions |
| `roles.PlatformDeployer` | `AdministratorAccess` managed policy | Trusted by management + platform account roots; used by Terragrunt providers |
| `roles.DeveloperAccess` | EKS describe only | Trusted by management + platform SSO PowerUserAccess and AdministratorAccess; 4-hour sessions |

## Commands

```bash
# Plan (bootstrap — direct SSO, no cross-account role)
AWS_PROFILE=platform terragrunt plan

# Apply (bootstrap — direct SSO, no cross-account role)
AWS_PROFILE=platform terragrunt apply
```
