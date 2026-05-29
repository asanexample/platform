# SSM Bastion

Deploys a lightweight EC2 bastion host accessible only via AWS Systems Manager Session Manager for private EKS API access.

## Module

`infra/modules/aws/ssm-bastion`

## Dependencies

- `networking` -- `../networking`
- `eks` -- `../eks`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `name` | `platform-use1-ssm-bastion` | |
| `subnet_id` | First kubernetes subnet | Placed in same subnet tier as EKS nodes |
| `cluster_security_group_id` | From EKS dependency | Adds ingress rule so bastion can reach the EKS API server |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
