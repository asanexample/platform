# GitHub OIDC

Creates an IAM OIDC identity provider and role for GitHub Actions to push container images to ECR.

## Module

`infra/modules/aws/github_oidc`

## Dependencies

- `ecr` -- `../ecr`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `github_org` | `asanexample` | |
| `github_repos` | `app-alpha`, `app-bravo` | Repos allowed to assume the role |
| `github_events` | `pull_request` | Scoped to PR events only |
| `role_name` | `github-actions-ecr-push` | |
| `inline_policy` | ECR auth + push permissions | `ecr:GetAuthorizationToken` + push actions scoped to ECR repository ARNs from ecr dependency |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
