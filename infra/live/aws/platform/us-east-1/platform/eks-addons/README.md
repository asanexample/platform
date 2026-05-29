# EKS Addons

Deploys EKS managed add-ons (coredns, aws-ebs-csi-driver) after CNI and nodes are ready.

## Module

`infra/modules/aws/eks-addons`

## Dependencies

- `eks` -- `../eks`
- `cilium` -- `../cilium`
- `node_groups` -- `../node-groups`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `addons.coredns` | `{}` | Default config; requires CNI + nodes to schedule pods |
| `addons.aws-ebs-csi-driver` | IRSA config | Creates IRSA role with `AmazonEBSCSIDriverPolicy` for `ebs-csi-controller-sa` in `kube-system` |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
