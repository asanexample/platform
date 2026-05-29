# ArgoCD Apps

Creates ArgoCD Applications and ApplicationSets for tenant workloads deployed to the preprod cluster.

## Module

`infra/modules/argocd-apps`

## Dependencies

- `eks` -- `../eks`
- `argocd` -- `../argocd`
- `argocd_clusters` -- `../argocd-clusters`
- `preprod_eks` -- `../../../../preprod/us-east-1/platform/eks` (cross-environment: preprod cluster endpoint)

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `tenants` | Loaded from preprod `teams.hcl` | Team/app definitions with mode and apps map |
| `github_org` | `gangster` | |
| `ecr_registry` | `829808296602.dkr.ecr.us-east-1.amazonaws.com` | Platform account ECR |
| `preview_domain` | `preprod.aws.refplat.org` | PR preview environment domain |
| `cluster_name` | `preprod` | Target cluster for app deployments |
| `cluster_server` | Preprod EKS endpoint | From preprod EKS dependency |

Also generates a `kubernetes_secret_v1` for GitHub ApplicationSet PR generator token (PAT from Secrets Manager).

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
