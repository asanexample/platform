# eks

Deploys the EKS control plane for the preprod account. Uses BYOCNI (Cilium) — no default CNI or kube-proxy is installed.

## Module

`infra/modules/aws/eks`

## Dependencies

- `networking` — `../networking`
- `iam_roles` — `../iam-roles`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `cluster_name` | `preprod-use1-eks` | |
| `endpoint_private_access` | `true` | |
| `endpoint_public_access` | `true` | Public access still enabled in preprod |
| `eks_addons` | `{}` | Addons deployed separately via `eks-addons` unit |
| `access_entries` | PlatformAdmin, PlatformDeployer, ArgoCD, DeveloperAccess, break-glass | ArgoCD entry allows cross-account management from platform hub; DeveloperAccess is namespace-scoped to team namespaces (from `teams.hcl`) |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
