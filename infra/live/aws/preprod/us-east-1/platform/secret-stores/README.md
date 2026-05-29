# secret-stores

Deploys ClusterSecretStore resources that connect External Secrets Operator to the AWS Secrets Manager and SSM backends in the preprod account.

## Module

`infra/modules/secret-stores`

## Dependencies

- `eks` — `../eks`
- `external_secrets` — `../external-secrets`
- `node_groups` — `../node-groups`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `region` | From base locals | AWS region for the secret store backend |
| `service_account_namespace` | From external-secrets output | Namespace where ESO service account lives |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
