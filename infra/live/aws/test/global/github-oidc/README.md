# GitHub OIDC

Configures GitHub Actions OIDC federation for the test account, allowing CI workflows to assume an IAM role without long-lived credentials.

## Module

`infra/modules/aws/github_oidc`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `github_org` | `asanexample` | GitHub organization |
| `github_repo` | `platform` | Repository allowed to assume the role |
| `github_branches` | `["main", "refs/heads/feat/*"]` | Branch restrictions for OIDC trust |
| `role_name` | `github-actions-terratest` | IAM role name assumed by CI |
| `role_policy_arns` | `AdministratorAccess` | Broad access for Terratest apply/destroy cycles |
| `max_session_duration` | `3600` | 1-hour session limit |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
