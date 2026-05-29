# cert-manager

Deploys cert-manager for automated TLS certificate provisioning in the preprod cluster via Let's Encrypt DNS-01 challenges.

## Module

`infra/modules/cert-manager`

## Dependencies

- `eks` — `../eks`
- `node_groups` — `../node-groups`
- `route53` — `../route53`

## Key Inputs

| Input                     | Value                     | Notes                                  |
|---------------------------|---------------------------|----------------------------------------|
| `route53_hosted_zone_arn` | From route53 dependency   | Scopes IRSA to the preprod hosted zone |
| `helm_chart_version`      | Pinned in `_versions.hcl` | Currently 1.17.1                       |
| `helm_wait`               | `true`                    | Blocks until pods are ready            |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
