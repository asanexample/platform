# Route53 Delegation

Creates NS delegation records in a parent Route53 hosted zone to delegate subdomains to child hosted zones. Used to connect environment-specific zones (e.g., `preprod.aws.refplat.org`) back to the parent zone (e.g., `aws.refplat.org`) so DNS resolution chains correctly across the zone hierarchy.

## Usage

```hcl
module "route53_delegation" {
  source = "../../modules/aws/route53_delegation"

  parent_zone_id = module.route53.zone_id

  delegations = {
    "preprod.aws.refplat.org" = [
      "ns-123.awsdns-01.com.",
      "ns-456.awsdns-02.net.",
      "ns-789.awsdns-03.org.",
      "ns-012.awsdns-04.co.uk.",
    ]
  }
}
```

## Examples

### Disabled Module

```hcl
module "route53_delegation" {
  source = "../../modules/aws/route53_delegation"
  create = false

  parent_zone_id = "Z00000000000000000000"
}
```

### Multiple Delegations

```hcl
module "route53_delegation" {
  source = "../../modules/aws/route53_delegation"

  parent_zone_id = module.route53.zone_id
  ttl            = 86400

  delegations = {
    "preprod.aws.refplat.org" = module.preprod_route53.name_servers
    "prod.aws.refplat.org"    = module.prod_route53.name_servers
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.delegation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_parent_zone_id"></a> [parent\_zone\_id](#input\_parent\_zone\_id) | Route53 zone ID of the parent zone (e.g. aws.refplat.org) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create delegation records | `bool` | `true` | no |
| <a name="input_delegations"></a> [delegations](#input\_delegations) | Map of subdomain FQDN to list of nameservers (e.g. { 'preprod.aws.refplat.org' = ['ns-123.awsdns-01.com.', ...] }) | `map(list(string))` | `{}` | no |
| <a name="input_ttl"></a> [ttl](#input\_ttl) | TTL for NS delegation records | `number` | `172800` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_delegation_records"></a> [delegation\_records](#output\_delegation\_records) | Map of delegated subdomains to their NS records |
<!-- END_TF_DOCS -->

## Notes

- The default TTL for NS delegation records is 172800 seconds (48 hours), which is standard for NS records.
- This module runs in the account that owns the parent zone, referencing name servers from child zones that may be in different accounts.
- The `delegations` map keys are the subdomain FQDNs and values are lists of name server hostnames from the child zone's `name_servers` output.

## Related ADRs

- ADR-030: Route53 Subdomain Delegation for Environment DNS
