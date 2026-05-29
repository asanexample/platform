# ExternalDNS

Deploys ExternalDNS to automatically manage Route53 DNS records from Kubernetes resources.

## Module

`infra/modules/external-dns`

## Dependencies

- `eks` -- `../eks`
- `node_groups` -- `../node-groups`
- `route53` -- `../route53`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `route53_hosted_zone_arn` | From route53 dependency | Scopes IRSA permissions to the platform hosted zone |
| `domain_filters` | `["aws.refplat.org"]` | Only manages records under this domain |
| `helm_wait` | `true` | |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
