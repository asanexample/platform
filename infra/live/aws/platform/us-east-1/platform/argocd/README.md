# ArgoCD

Deploys ArgoCD for GitOps-based continuous delivery in the platform cluster.

## Module

`infra/modules/argocd`

## Dependencies

- `eks` -- `../eks`
- `node_groups` -- `../node-groups`
- `preprod_iam_roles` -- `../../../../preprod/us-east-1/platform/iam-roles` (cross-environment: preprod account ArgoCD role)

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `high_availability` | `false` | Single-replica mode |
| `dex_enabled` | `true` | SSO via Dex SAML connector to AWS Identity Center |
| `rbac_policy_csv` | Custom CSV | Maps IAM Identity Center group IDs to ArgoCD roles (admin, developer, readonly) |
| `argocd_cm_extra` | SAML connector config | Dex SAML connector pointing to `argocd.aws.refplat.org` with AWS SSO |
| `remote_cluster_role_arns` | Preprod ArgoCD role ARN | Allows ArgoCD to assume into preprod for cross-cluster deployments |
| `helm_wait` | `false` | |

Also generates a `kubernetes_secret_v1` for GitHub repo credentials (PAT from Secrets Manager `platform/github/argocd-pat`).

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
