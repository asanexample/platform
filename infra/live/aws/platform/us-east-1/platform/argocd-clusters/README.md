# ArgoCD Clusters

Registers remote clusters (preprod) as ArgoCD deployment targets via Kubernetes secrets.

## Module

`infra/modules/argocd-clusters`

## Dependencies

- `eks` -- `../eks`
- `argocd` -- `../argocd`
- `node_groups` -- `../node-groups`
- `preprod_eks` -- `../../../../preprod/us-east-1/platform/eks` (cross-environment: preprod cluster details)
- `preprod_iam_roles` -- `../../../../preprod/us-east-1/platform/iam-roles` (cross-environment: preprod ArgoCD role)

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `clusters` | `{ preprod = { ... } }` | Registers preprod EKS as an ArgoCD cluster target |
| `clusters.preprod.aws_auth` | Preprod cluster name + ArgoCD role ARN | Uses `aws eks get-token` exec-based auth for cross-account access |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
