# Cross-VPC DNS

Provides DNS resolution across VPCs connected via Transit Gateway. Supports three modes via the `dns_method` variable: Private Hosted Zones (`phz`) with static or dynamically-resolved A records, Route53 Resolver outbound endpoints (`resolver_outbound`) with forwarding rules, and Route53 Resolver inbound endpoints (`resolver_inbound`) for receiving forwarded queries. The PHZ mode can dynamically look up EKS API server ENI IPs via the AWS CLI, including cross-account lookups using STS role assumption.

## Usage

```hcl
module "cross_vpc_dns" {
  source = "../../modules/aws/cross-vpc-dns"

  name       = "platform-use1"
  dns_method = "phz"
  vpc_id     = module.networking.vpc_id

  phz_records = {
    eks = {
      domain              = "ABCDEF1234.gr7.us-east-1.eks.amazonaws.com"
      eks_cluster_name    = "preprod-use1-eks"
      eks_lookup_role_arn = "arn:aws:iam::<PREPROD_ACCOUNT_ID>:role/PlatformDeployer"
      ttl                 = 60
    }
  }

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "cross_vpc_dns" {
  source = "../../modules/aws/cross-vpc-dns"
  create = false

  name   = "unused"
  vpc_id = "vpc-xxx"
}
```

### Resolver Outbound (Source VPC)

```hcl
module "cross_vpc_dns_outbound" {
  source = "../../modules/aws/cross-vpc-dns"

  name       = "platform-use1"
  dns_method = "resolver_outbound"
  vpc_id     = module.networking.vpc_id

  resolver_subnet_ids = [
    module.networking.subnet_ids["transit-a"],
    module.networking.subnet_ids["transit-b"],
  ]

  forwarding_rules = {
    preprod-eks = {
      domain     = "ABCDEF1234.gr7.us-east-1.eks.amazonaws.com"
      target_ips = ["10.200.0.10", "10.200.0.11"]
    }
  }

  tags = {
    Environment = "platform"
  }
}
```

### Resolver Inbound (Target VPC)

```hcl
module "cross_vpc_dns_inbound" {
  source = "../../modules/aws/cross-vpc-dns"

  name       = "preprod-use1"
  dns_method = "resolver_inbound"
  vpc_id     = module.networking.vpc_id

  resolver_subnet_ids = [
    module.networking.subnet_ids["transit-a"],
    module.networking.subnet_ids["transit-b"],
  ]

  resolver_allowed_cidrs = ["10.100.0.0/16"]

  tags = {
    Environment = "preprod"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | >= 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_external"></a> [external](#provider\_external) | >= 2.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_resolver_endpoint.inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule) | resource |
| [aws_route53_resolver_rule_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_rule_association) | resource |
| [aws_route53_zone.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_security_group.resolver_inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.resolver_outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.resolver_inbound_ingress_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.resolver_inbound_ingress_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.resolver_outbound_egress_tcp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.resolver_outbound_egress_udp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [external_external.eks_eni_ips](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for DNS resources | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to associate PHZ or resolver endpoint with | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_dns_method"></a> [dns\_method](#input\_dns\_method) | DNS resolution method: phz, resolver\_outbound, or resolver\_inbound | `string` | `"phz"` | no |
| <a name="input_forwarding_rules"></a> [forwarding\_rules](#input\_forwarding\_rules) | Map of name to forwarding rule. Only used with resolver\_outbound. | <pre>map(object({<br/>    domain     = string<br/>    target_ips = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_phz_records"></a> [phz\_records](#input\_phz\_records) | Map of name to PHZ config. Provide either static ips or eks\_cluster\_name for dynamic ENI lookup (requires eks\_lookup\_role\_arn for cross-account). | <pre>map(object({<br/>    domain              = string<br/>    ips                 = optional(list(string), [])<br/>    eks_cluster_name    = optional(string, "")<br/>    eks_lookup_role_arn = optional(string, "")<br/>    ttl                 = optional(number, 60)<br/>  }))</pre> | `{}` | no |
| <a name="input_resolver_allowed_cidrs"></a> [resolver\_allowed\_cidrs](#input\_resolver\_allowed\_cidrs) | CIDRs allowed to query the inbound endpoint (e.g. platform VPC CIDR) | `list(string)` | `[]` | no |
| <a name="input_resolver_subnet_ids"></a> [resolver\_subnet\_ids](#input\_resolver\_subnet\_ids) | Subnet IDs for resolver ENIs (min 2, different AZs). Used by both outbound and inbound. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_phz_zone_ids"></a> [phz\_zone\_ids](#output\_phz\_zone\_ids) | Map of record name to private hosted zone ID |
| <a name="output_resolver_inbound_endpoint_id"></a> [resolver\_inbound\_endpoint\_id](#output\_resolver\_inbound\_endpoint\_id) | Inbound resolver endpoint ID |
| <a name="output_resolver_inbound_ips"></a> [resolver\_inbound\_ips](#output\_resolver\_inbound\_ips) | Map of subnet ID to inbound endpoint IP (use as forwarding rule targets) |
| <a name="output_resolver_outbound_endpoint_id"></a> [resolver\_outbound\_endpoint\_id](#output\_resolver\_outbound\_endpoint\_id) | Outbound resolver endpoint ID |
<!-- END_TF_DOCS -->

## Notes

- PHZ mode is the cheapest option but requires manual IP updates if the EKS cluster is recreated, unless dynamic ENI lookup is used via `eks_cluster_name`.
- Resolver endpoints cost approximately $365/month for 4 ENIs (2 per direction) but handle DNS changes automatically.
- Dynamic ENI lookup uses a `data "external"` source that shells out to the AWS CLI; the runner must have `aws` CLI available and valid credentials.
- EKS-managed Route53 Private Hosted Zones are inaccessible via standard APIs, which is why this module maintains its own zones rather than associating the EKS-managed ones.
- Resolver endpoints require at least 2 subnet IDs in different availability zones.

## Related ADRs

- ADR-035: Cross-VPC DNS Resolution for Private EKS Endpoints
- ADR-022: DNS Architecture
