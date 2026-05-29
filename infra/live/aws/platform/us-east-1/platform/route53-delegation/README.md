# Route53 Delegation

Creates NS delegation records in the platform `aws.refplat.org` zone to delegate subdomains to child environment zones.

## Module

`infra/modules/aws/route53_delegation`

## Dependencies

- `route53` -- `../route53`
- `preprod_route53` -- `../../../../preprod/us-east-1/platform/route53` (cross-environment: preprod zone name servers)

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `parent_zone_id` | From platform route53 | The `aws.refplat.org` zone |
| `delegations` | `preprod.aws.refplat.org` -> preprod NS records | Delegates preprod subdomain to preprod's own Route53 zone |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
