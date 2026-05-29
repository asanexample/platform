# Cross-VPC DNS

Creates a private hosted zone (PHZ) in the platform VPC to resolve the preprod EKS private API endpoint across the Transit Gateway.

## Module

`infra/modules/aws/cross-vpc-dns`

## Dependencies

- `networking` -- `../networking`
- `preprod_eks` -- `../../../../preprod/us-east-1/platform/eks` (cross-environment: preprod cluster endpoint and security group)

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `dns_method` | `phz` | Private Hosted Zone with A records (cheaper than Resolver endpoints) |
| `phz_records.preprod-eks` | Preprod EKS endpoint domain | Dynamically looks up EKS ENI IPs via `eks_lookup_role_arn` in preprod account |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
