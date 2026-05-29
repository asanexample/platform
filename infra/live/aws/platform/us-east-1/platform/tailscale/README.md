# Tailscale

Deploys the Tailscale Kubernetes Operator as a subnet router for VPN access to the platform VPC and private EKS API.

## Module

`infra/modules/tailscale`

## Dependencies

- `eks` -- `../eks`
- `node_groups` -- `../node-groups`
- `external_secrets` -- `../external-secrets`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `advertise_routes` | `10.100.0.0/16` | Advertises the entire platform VPC CIDR to the tailnet |
| `split_dns` | `us-east-1.eks.amazonaws.com` -> `10.100.0.2`, `aws.refplat.org` -> `10.100.0.2` | Routes DNS queries for EKS and platform domains through the VPC DNS resolver |

OAuth credentials and API key are sourced from Secrets Manager (`platform/tailscale/oauth`, `platform/tailscale/api-key`).

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
