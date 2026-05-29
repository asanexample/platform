# EKS

Deploys the EKS control plane in BYOCNI mode (no default CNI -- Cilium is deployed separately).

## Module

`infra/modules/aws/eks`

## Dependencies

- `networking` -- `../networking`
- `iam_roles` -- `../iam-roles`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `cluster_name` | `platform-use1-eks` | |
| `endpoint_private_access` | `true` | |
| `endpoint_public_access` | `false` | Fully private API; access via Tailscale VPN or SSM bastion |
| `eks_addons` | `{}` | No managed addons at cluster creation; coredns deployed via separate eks-addons unit |
| `access_entries` | PlatformAdmin, PlatformDeployer, break-glass | Three access entries with cluster admin policy |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
