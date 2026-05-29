# Cloudflare DNS

Delegates the `aws.refplat.org` subdomain from Cloudflare to the platform Route53 hosted zone via NS records.

## Module

`infra/modules/cloudflare/dns_delegation`

## Dependencies

- `route53` -- `../route53`

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `cloudflare_zone_id` | From `common.hcl` | Cloudflare zone for `refplat.org` |
| `subdomain` | `aws` | Creates NS delegation for `aws.refplat.org` |
| `nameservers` | From route53 dependency | Route53 hosted zone NS records |

Cloudflare API token is sourced from Secrets Manager (`platform/cloudflare/api-token`).

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
