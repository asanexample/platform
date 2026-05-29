# Networking

Deploys the VPC, subnets, NAT gateways, and flow logs for the prod environment.

## Module

`infra/modules/aws/networking`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `create` | `false` | Unit is defined but not yet deployed |
| `create_internet_gateway` | `true` | Public internet access via IGW |
| `create_nat_gateways` | `true` | Private subnet outbound access |
| `single_nat_gateway` | `false` | One NAT gateway per AZ for HA |
| `enable_eks_networking` | `true` | Adds EKS-required subnet tags |
| `enable_flow_logs` | `true` | VPC flow logs with 90-day retention |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
