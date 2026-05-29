# route53

Creates the Route53 public hosted zone for the preprod subdomain with CAA records restricting certificate issuance to Let's Encrypt.

## Module

`infra/modules/aws/route53`

## Dependencies

None

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `domain_name` | `"preprod.aws.refplat.org"` | Delegated from platform's `aws.refplat.org` zone |
| `force_destroy` | `true` | Allows zone deletion even with records |
| `caa_records` | Let's Encrypt issue/issuewild + iodef | Restricts TLS cert issuance to Let's Encrypt only |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
