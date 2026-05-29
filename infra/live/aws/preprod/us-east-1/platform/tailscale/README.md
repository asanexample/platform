# tailscale

Deploys the Tailscale Kubernetes Operator as a subnet router for VPN access to the preprod VPC and private EKS API. OAuth credentials are sourced from AWS Secrets Manager.

## Module

`infra/modules/tailscale`

## Dependencies

- `eks` — `../eks`
- `node_groups` — `../node-groups`
- `external_secrets` — `../external-secrets`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `advertise_routes` | `["10.101.0.0/16"]` | Advertises the preprod VPC CIDR to the tailnet |
| `split_dns` | `us-east-1.eks.amazonaws.com` and `preprod.aws.refplat.org` pointing to `10.101.0.2` | Resolves EKS API and preprod services via VPC DNS |
| `helm_chart_version` | Pinned in `_versions.hcl` | Currently 1.96.5 |

## Notes

- Generated providers pull API key and OAuth credentials from `preprod/tailscale/api-key` and `preprod/tailscale/oauth` in Secrets Manager.
- Tailnet: `taild3190d.ts.net`

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
