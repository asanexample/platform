# networking

Deploys the VPC, subnets, NAT gateway, internet gateway, VPC endpoints, and flow logs for the preprod account.

## Module

`infra/modules/aws/networking`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `vpc_name` | `preprod-use1-vpc` | |
| `address_space` | From `network.hcl` | Preprod CIDR (10.101.0.0/16) |
| `subnets` | From `network.hcl` | Kubernetes, transit, and other subnet tiers |
| `single_nat_gateway` | `true` | Cost optimization — single NAT for preprod |
| `enable_eks_networking` | `true` | Adds EKS-required subnet tags |
| `eks_cluster_name` | `preprod-use1-eks` | |
| `interface_vpc_endpoints` | secretsmanager, ssm, sts, kms | Private access to AWS services |
| `enable_flow_logs` | `true` | 30-day retention |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
