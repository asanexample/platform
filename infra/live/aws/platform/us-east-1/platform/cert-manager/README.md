# cert-manager

Deploys cert-manager for automated TLS certificate provisioning via Let's Encrypt DNS-01 challenges.

## Module

`infra/modules/cert-manager`

## Dependencies

- `eks` -- `../eks`
- `node_groups` -- `../node-groups`
- `route53` -- `../route53`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `route53_hosted_zone_arn` | From route53 dependency | Scopes IRSA permissions for DNS-01 challenge validation |
| `helm_wait` | `true` | Waits for pods to be ready before completing |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
