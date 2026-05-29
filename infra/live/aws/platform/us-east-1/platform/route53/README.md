# Route53

Creates the `aws.refplat.org` public hosted zone in the platform account.

## Module

`infra/modules/aws/route53`

## Dependencies

None.

## Key Inputs

| Input | Value | Notes |
|-------|-------|-------|
| `domain_name` | `aws.refplat.org` | |
| `force_destroy` | `true` | Allows zone deletion even with records present |
| `caa_records` | Let's Encrypt only | Restricts certificate issuance to `letsencrypt.org`; iodef reports to `josh@deeden.org` |

## Commands

```bash
# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```
