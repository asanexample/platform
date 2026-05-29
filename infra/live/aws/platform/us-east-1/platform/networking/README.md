# Networking

Deploys the VPC, subnets, gateways, VPC endpoints, and flow logs for the platform environment.

## Module

`infra/modules/aws/networking`

## Dependencies

None.

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `vpc_name` | `platform-use1-vpc` | |
| `address_space` | From `network.hcl` | `10.100.0.0/16` |
| `subnets` | From `network.hcl` | 6 tiers per AZ: kubernetes, endpoints, firewall, services, public, transit |
| `single_nat_gateway` | `true` | Cost-efficient; single NAT for all private subnets |
| `enable_eks_networking` | `true` | Pre-tags subnets and creates security groups for EKS |
| `interface_vpc_endpoints` | `secretsmanager`, `ssm`, `sts`, `kms` | Private access to AWS APIs without NAT |
| `enable_flow_logs` | `true` | 30-day retention |

Has a `before_hook` on apply to clean up orphaned VPC flow log groups (assumes into platform account via STS).

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
