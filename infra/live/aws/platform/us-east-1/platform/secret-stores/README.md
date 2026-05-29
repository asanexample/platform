# Secret Stores

Creates ESO ClusterSecretStore resources that connect the External Secrets Operator to AWS Secrets Manager and SSM Parameter Store backends.

## Module

`infra/modules/secret-stores`

## Dependencies

- `eks` -- `../eks`
- `external_secrets` -- `../external-secrets`
- `node_groups` -- `../node-groups`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `region` | `us-east-1` | AWS region for the secrets backend |
| `service_account_namespace` | From external-secrets dependency | Namespace where ESO service account lives |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
