# ssm-bastion

Deploys an SSM-managed bastion EC2 instance for private EKS API access via Session Manager port forwarding. No SSH keys or public IPs required.

## Module

`infra/modules/aws/ssm-bastion`

## Dependencies

- `networking` — `../networking`
- `eks` — `../eks`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `name` | `preprod-use1-ssm-bastion` | |
| `subnet_id` | First kubernetes subnet | Placed in a private subnet |
| `cluster_security_group_id` | From EKS output | Allows bastion to reach EKS API |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
