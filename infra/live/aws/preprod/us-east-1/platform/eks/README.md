# eks

Deploys the EKS control plane for the preprod account. Uses BYOCNI (Cilium) — no default CNI or kube-proxy is installed.

## Module

`infra/modules/aws/eks`

## Dependencies

- `networking` — `../networking`
- `iam_roles` — `../iam-roles`

## Key Inputs

| Input                     | Value                                                                 | Notes                                                                                                                                     |
|---------------------------|-----------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------|
| `cluster_name`            | `preprod-use1-eks`                                                    |                                                                                                                                           |
| `endpoint_private_access` | `true`                                                                |                                                                                                                                           |
| `endpoint_public_access`  | `true`                                                                | Public access still enabled in preprod                                                                                                    |
| `eks_addons`              | `{}`                                                                  | Addons deployed separately via `eks-addons` unit                                                                                          |
| `access_entries`          | PlatformAdmin, PlatformDeployer, ArgoCD, break-glass, one `developer_<team>` per team | ArgoCD entry allows cross-account management from platform hub; each `developer_<team>` group-maps `DeveloperAccess-<team>` to `team-<team>:developers` (RBAC lives in the tenant module's RoleBinding — ADR-039). Generated from `teams.hcl` |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
