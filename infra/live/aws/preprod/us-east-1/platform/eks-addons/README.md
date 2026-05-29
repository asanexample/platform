# eks-addons

Deploys EKS managed add-ons (coredns, aws-ebs-csi-driver) after CNI and nodes are ready. Separated from the EKS unit because BYOCNI requires pods to schedule only after Cilium and node groups are up.

## Module

`infra/modules/aws/eks-addons`

## Dependencies

- `eks` — `../eks`
- `cilium` — `../cilium`
- `node_groups` — `../node-groups`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `addons.coredns` | `{}` | Default configuration |
| `addons.aws-ebs-csi-driver` | IRSA with `AmazonEBSCSIDriverPolicy` | Creates a service account for the EBS CSI driver |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
