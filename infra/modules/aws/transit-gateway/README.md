# Transit Gateway

Creates or attaches to an AWS Transit Gateway for cross-VPC connectivity. Operates in two modes: hub mode (`create_tgw = true`) creates the Transit Gateway and shares it via RAM to spoke accounts, and spoke mode (`create_tgw = false`) accepts a RAM share and attaches a VPC to an existing Transit Gateway. In both modes, the module creates a VPC attachment, adds routes to specified route tables pointing at the TGW, and optionally adds security group ingress rules for cross-VPC HTTPS traffic.

## Usage

```hcl
module "transit_gateway" {
  source = "../../modules/aws/transit-gateway"

  name       = "platform-use1-tgw"
  create_tgw = true
  vpc_id     = module.networking.vpc_id
  subnet_ids = [
    module.networking.subnet_ids["transit-a"],
    module.networking.subnet_ids["transit-b"],
  ]

  amazon_side_asn      = 64512
  ram_share_principals = ["620830101009", "554518885123"]

  route_table_ids = module.networking.private_route_table_ids
  destination_cidrs = ["10.200.0.0/16"]

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "transit_gateway" {
  source = "../../modules/aws/transit-gateway"
  create = false

  name       = "unused"
  vpc_id     = "vpc-xxx"
  subnet_ids = []
}
```

### Spoke Mode

```hcl
module "transit_gateway" {
  source = "../../modules/aws/transit-gateway"

  name               = "preprod-use1-tgw"
  create_tgw         = false
  transit_gateway_id = "tgw-0abc123def456"
  ram_share_arn      = "arn:aws:ram:us-east-1:829808296602:resource-share/abc-123"

  vpc_id     = module.networking.vpc_id
  subnet_ids = [
    module.networking.subnet_ids["transit-a"],
    module.networking.subnet_ids["transit-b"],
  ]

  route_table_ids   = module.networking.private_route_table_ids
  destination_cidrs = ["10.100.0.0/16"]

  security_group_id            = module.networking.eks_security_group_id
  security_group_ingress_cidrs = ["10.100.0.0/16"]

  tags = {
    Environment = "preprod"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ec2_transit_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_ram_principal_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_principal_association) | resource |
| [aws_ram_resource_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_association) | resource |
| [aws_ram_resource_share.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_share) | resource |
| [aws_ram_resource_share_accepter.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ram_resource_share_accepter) | resource |
| [aws_route.tgw](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_security_group_rule.tgw_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for transit gateway resources | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the TGW attachment (one per AZ, use transit subnets) | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to attach to the Transit Gateway | `string` | n/a | yes |
| <a name="input_amazon_side_asn"></a> [amazon\_side\_asn](#input\_amazon\_side\_asn) | Private ASN for the Transit Gateway | `number` | `64512` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_tgw"></a> [create\_tgw](#input\_create\_tgw) | Create the Transit Gateway (hub mode). False for spoke mode. | `bool` | `false` | no |
| <a name="input_destination_cidrs"></a> [destination\_cidrs](#input\_destination\_cidrs) | CIDR blocks to route via the Transit Gateway | `list(string)` | `[]` | no |
| <a name="input_ram_share_arn"></a> [ram\_share\_arn](#input\_ram\_share\_arn) | ARN of the RAM resource share to accept (spoke mode only) | `string` | `null` | no |
| <a name="input_ram_share_principals"></a> [ram\_share\_principals](#input\_ram\_share\_principals) | AWS account IDs to share the TGW with via RAM (hub mode only) | `list(string)` | `[]` | no |
| <a name="input_route_table_ids"></a> [route\_table\_ids](#input\_route\_table\_ids) | Map of route table name to ID for adding TGW routes | `map(string)` | `{}` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | Security group ID to add ingress rules to (e.g. EKS cluster SG) | `string` | `null` | no |
| <a name="input_security_group_ingress_cidrs"></a> [security\_group\_ingress\_cidrs](#input\_security\_group\_ingress\_cidrs) | CIDR blocks to allow inbound on port 443 | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | Existing TGW ID (spoke mode, required when create\_tgw is false) | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ram_share_arn"></a> [ram\_share\_arn](#output\_ram\_share\_arn) | The ARN of the RAM resource share |
| <a name="output_transit_gateway_arn"></a> [transit\_gateway\_arn](#output\_transit\_gateway\_arn) | The ARN of the Transit Gateway |
| <a name="output_transit_gateway_id"></a> [transit\_gateway\_id](#output\_transit\_gateway\_id) | The ID of the Transit Gateway |
| <a name="output_vpc_attachment_id"></a> [vpc\_attachment\_id](#output\_vpc\_attachment\_id) | The ID of the VPC attachment |
<!-- END_TF_DOCS -->

## Notes

- Hub mode enables auto-accept for shared attachments, default route table association/propagation, DNS support, and VPN ECMP support.
- RAM sharing uses `allow_external_principals = true` to share across AWS accounts within the organization.
- Subnet IDs should point to dedicated `/28` transit subnets (one per AZ) reserved for TGW ENIs, not workload subnets.
- The `security_group_ingress_cidrs` variable adds port 443 ingress rules, which is useful for allowing cross-VPC EKS API access through the TGW.
- In spoke mode, the RAM share must be accepted before the VPC attachment can be created; the module handles this ordering via `depends_on`.

## Related ADRs

- ADR-034: Transit Gateway for Cross-Account VPC Connectivity
