# gateway-config

Deploys the Cilium Gateway API configuration (Gateway resource, TLS certificates, HTTPRoutes) for the preprod cluster.

## Module

`infra/modules/gateway-config`

## Dependencies

- `eks` — `../eks`
- `cilium` — `../cilium`
- `cert_manager` — `../cert-manager`
- `external_dns` — `../external-dns`
- `route53` — `../route53`

## Key Inputs

| Input               | Value                       | Notes                                                         |
|---------------------|-----------------------------|---------------------------------------------------------------|
| `domain`            | `"preprod.aws.refplat.org"` |                                                               |
| `internal`          | `false`                     | Public-facing NLB (differs from platform's internal gateway)  |
| `gateway_name`      | `"preprod-gateway"`         |                                                               |
| `letsencrypt_email` | `"josh@deeden.org"`         | For Let's Encrypt DNS-01 certificate issuance                 |
| `routes`            | `{}`                        | No platform-level routes; tenant routes added via tenant unit |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
