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

Also generates an `ExternalSecret` for GitHub repo credentials via a **GitHub App** (TD2-02b) — ArgoCD mints +
auto-refreshes installation tokens itself, so there is no PAT to expire. The App's `{appId, installationId,
privateKey}` live in Secrets Manager (`platform/argocd/github-app`); ESO projects them into the
`github-asanexample-app-creds` repo-creds secret (private key never enters terraform state). The retired
`platform/github/argocd-pat` secret can be deleted once this is applied.

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
