# node-groups

Deploys EKS managed node groups for the preprod cluster. Depends on Cilium being ready — nodes cannot join until the CNI is installed (BYOCNI).

## Module

`infra/modules/aws/eks-node-group`

## Dependencies

- `networking` — `../networking`
- `eks` — `../eks`
- `cilium` — `../cilium`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `node_groups.system` | t3.large, 2-4 nodes | Labeled `node-role=system` |
| `node_groups.workload` | t3.large, 1-6 nodes | Labeled `node-role=workload` |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
