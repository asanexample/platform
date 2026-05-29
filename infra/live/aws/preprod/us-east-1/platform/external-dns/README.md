# external-dns

Deploys ExternalDNS to automatically manage Route53 DNS records for Kubernetes services and ingress in the preprod cluster.

## Module

`infra/modules/external-dns`

## Dependencies

- `eks` — `../eks`
- `node_groups` — `../node-groups`
- `route53` — `../route53`

## Key Inputs

| Input                     | Value                         | Notes                               |
|---------------------------|-------------------------------|-------------------------------------|
| `route53_hosted_zone_arn` | From route53 dependency       | Scopes IRSA permissions             |
| `domain_filters`          | `["preprod.aws.refplat.org"]` | Only manages records in this domain |
| `helm_chart_version`      | Pinned in `_versions.hcl`     | Currently 1.16.1                    |
| `helm_wait`               | `true`                        | Blocks until pods are ready         |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
