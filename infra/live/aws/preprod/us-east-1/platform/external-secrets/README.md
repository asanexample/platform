# external-secrets

Deploys External Secrets Operator to sync secrets from AWS Secrets Manager and SSM Parameter Store into Kubernetes secrets in the preprod cluster.

## Module

`infra/modules/external-secrets`

## Dependencies

- `eks` — `../eks`
- `node_groups` — `../node-groups`

## Key Inputs

| Input                | Value                     | Notes                                  |
|----------------------|---------------------------|----------------------------------------|
| `kms_key_arns`       | EKS KMS key ARN           | Allows decrypting EKS-managed secrets  |
| `secret_path_prefix` | `"preprod"`               | Scopes IRSA to `preprod/*` secrets     |
| `ssm_path_prefix`    | `"/preprod"`              | Scopes IRSA to `/preprod/*` parameters |
| `helm_chart_version` | Pinned in `_versions.hcl` | Currently 0.14.3                       |
| `helm_wait`          | `true`                    | Blocks until pods are ready            |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
