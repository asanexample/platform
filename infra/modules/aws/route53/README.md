# Route53

Creates a Route53 public hosted zone with optional CAA records to restrict which certificate authorities can issue certificates for the domain. This module manages only the zone and CAA records; delegation and application-specific DNS records are handled by other modules.

## Usage

```hcl
module "route53" {
  source = "../../modules/aws/route53"

  domain_name = "aws.refplat.org"

  caa_records = [
    "0 issue \"letsencrypt.org\"",
    "0 issue \"amazon.com\"",
  ]

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "route53" {
  source = "../../modules/aws/route53"
  create = false

  domain_name = "unused.example.com"
}
```

### Zone Without CAA Records

```hcl
module "route53" {
  source = "../../modules/aws/route53"

  domain_name = "preprod.aws.refplat.org"
  comment     = "PreProd environment hosted zone"

  tags = {
    Environment = "preprod"
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
| [aws_route53_record.caa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain name for the Route53 hosted zone | `string` | n/a | yes |
| <a name="input_caa_records"></a> [caa\_records](#input\_caa\_records) | CAA records restricting which CAs can issue certificates (e.g. '0 issue "letsencrypt.org"') | `list(string)` | `[]` | no |
| <a name="input_comment"></a> [comment](#input\_comment) | Comment for the hosted zone | `string` | `"Managed by OpenTofu"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the hosted zone | `bool` | `true` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Whether to destroy all records when destroying the zone | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_name_servers"></a> [name\_servers](#output\_name\_servers) | Name servers for the hosted zone (add these as NS records in your registrar) |
| <a name="output_zone_arn"></a> [zone\_arn](#output\_zone\_arn) | The hosted zone ARN |
| <a name="output_zone_id"></a> [zone\_id](#output\_zone\_id) | The hosted zone ID |
| <a name="output_zone_name"></a> [zone\_name](#output\_zone\_name) | The hosted zone name |
<!-- END_TF_DOCS -->

## Notes

- The `name_servers` output provides the NS records that must be added to the parent domain's registrar or parent hosted zone for delegation.
- Set `force_destroy = true` to allow zone deletion when records still exist (useful during teardowns).
- CAA records use a TTL of 3600 seconds (1 hour).

## Related ADRs

- ADR-022: DNS Architecture
- ADR-030: Route53 Subdomain Delegation for Environment DNS
