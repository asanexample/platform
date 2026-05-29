# External Secrets Operator

Deploys the External Secrets Operator (ESO) for syncing AWS Secrets Manager and SSM Parameter Store values into Kubernetes secrets.

## Module

`infra/modules/external-secrets`

## Dependencies

- `eks` -- `../eks`
- `node_groups` -- `../node-groups`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `kms_key_arns` | EKS KMS key ARN | Allows ESO to decrypt secrets encrypted with the cluster KMS key |
| `secret_path_prefix` | `platform` | Scopes Secrets Manager access to `platform/*` |
| `ssm_path_prefix` | `/platform` | Scopes SSM Parameter Store access to `/platform/*` |
| `helm_wait` | `true` | |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
