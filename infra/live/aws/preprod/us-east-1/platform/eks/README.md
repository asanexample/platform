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
| `access_entries`          | PlatformAdmin, PlatformDeployer, ArgoCD, break-glass | Static/platform access entries only. ArgoCD entry allows cross-account management from platform hub. Per-team `developer_<team>` access entries (group-mapping `DeveloperAccess-<team>` to `team-<team>:developers`) and their `team-<team>:developers` RoleBindings are provisioned by the Crossplane Tenant Composition (BACK stack P3) — the per-team `teams.hcl` loop was removed here |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
