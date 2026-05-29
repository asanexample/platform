# Cloudflare DNS Delegation

Creates NS records in a Cloudflare-managed parent zone to delegate a subdomain to external authoritative nameservers (e.g., AWS Route 53). This is the glue that connects cloud-specific hosted zones back to the top-level domain managed in Cloudflare. Each nameserver in the list gets its own NS record with a fixed 1-hour TTL.

## Usage

```hcl
module "dns_delegation" {
  source = "../../modules/cloudflare/dns_delegation"

  cloudflare_zone_id = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
  subdomain          = "aws"
  nameservers = [
    "ns-1234.awsdns-01.org",
    "ns-567.awsdns-02.co.uk",
    "ns-890.awsdns-03.net",
    "ns-111.awsdns-04.com",
  ]
}
```

## Examples

### Disabled Module

```hcl
module "dns_delegation" {
  source = "../../modules/cloudflare/dns_delegation"

  create             = false
  cloudflare_zone_id = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
  subdomain          = "aws"
  nameservers        = []
}
```

### Multiple Subdomain Delegations

```hcl
module "aws_delegation" {
  source = "../../modules/cloudflare/dns_delegation"

  cloudflare_zone_id = var.zone_id
  subdomain          = "aws"
  nameservers        = module.aws_route53.name_servers
}

module "azure_delegation" {
  source = "../../modules/cloudflare/dns_delegation"

  cloudflare_zone_id = var.zone_id
  subdomain          = "azure"
  nameservers        = module.azure_dns.name_servers
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_dns_record.ns](https://registry.terraform.io/providers/hashicorp/cloudflare/latest/docs/resources/dns_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cloudflare_zone_id"></a> [cloudflare\_zone\_id](#input\_cloudflare\_zone\_id) | Cloudflare zone ID for the parent domain | `string` | n/a | yes |
| <a name="input_nameservers"></a> [nameservers](#input\_nameservers) | List of authoritative nameservers for the subdomain | `list(string)` | n/a | yes |
| <a name="input_subdomain"></a> [subdomain](#input\_subdomain) | Subdomain to delegate (e.g. 'aws' for aws.refplat.org) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the delegation records | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_record_ids"></a> [record\_ids](#output\_record\_ids) | Map of nameserver to Cloudflare DNS record ID |
<!-- END_TF_DOCS -->

## Notes

- Each nameserver in the list creates a separate `cloudflare_dns_record` resource of type NS, so adds/removes are handled individually without affecting other records.
- TTL is hardcoded to 3600 seconds (1 hour). Change `main.tf` directly if a different TTL is needed.
- Requires the Cloudflare provider to be configured with an API token that has DNS edit permissions on the target zone.

## Related ADRs

- ADR-022: DNS Architecture
