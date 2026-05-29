# Node Groups

Deploys EKS managed node groups providing compute capacity for system and application workloads.

## Module

`infra/modules/aws/eks-node-group`

## Dependencies

- `networking` -- `../networking`
- `eks` -- `../eks`
- `cilium` -- `../cilium`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `node_groups.system` | `t3.large`, 2-4 nodes, label `node-role=system` | Platform components (ArgoCD, cert-manager, etc.) |
| `node_groups.workload` | `t3.large`, 1-6 nodes, label `node-role=workload` | Application workloads |

Both groups are placed in kubernetes subnets. Cilium dependency is structural -- nodes will not reach Ready without the CNI.

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
