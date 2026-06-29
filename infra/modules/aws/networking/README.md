# Networking

Creates an AWS VPC with configurable subnets, internet gateway, NAT gateways, route tables, S3 gateway endpoint, interface VPC endpoints, EKS-specific security groups and subnet tags, and VPC flow logs. Supports multiple network topologies: private (with NAT gateways for egress), public (direct IGW routing), and airgapped (no internet access). Each private subnet gets its own route table for per-AZ NAT gateway routing, with an option for a single shared NAT gateway to reduce costs.

## Usage

```hcl
module "networking" {
  source = "../../modules/aws/networking"

  vpc_name      = "vpc-platform-ops-use1"
  address_space = ["10.100.0.0/16"]

  subnets = {
    "snet-platform-ops-public-use1-a" = {
      address_prefixes  = ["10.100.0.0/24"]
      availability_zone = "us-east-1a"
      public            = true
    }
    "snet-platform-ops-public-use1-b" = {
      address_prefixes  = ["10.100.1.0/24"]
      availability_zone = "us-east-1b"
      public            = true
    }
    "snet-platform-ops-private-use1-a-kubernetes" = {
      address_prefixes  = ["10.100.10.0/24"]
      availability_zone = "us-east-1a"
    }
    "snet-platform-ops-private-use1-b-kubernetes" = {
      address_prefixes  = ["10.100.11.0/24"]
      availability_zone = "us-east-1b"
    }
  }

  enable_eks_networking = true
  eks_cluster_name      = "platform-use1-eks"

  interface_vpc_endpoints = ["secretsmanager", "ssm", "ssmmessages", "ec2messages", "sts"]

  tags = {
    Environment = "platform"
    ManagedBy   = "opentofu"
  }
}
```

## Examples

### Disabled Module

```hcl
module "networking" {
  source = "../../modules/aws/networking"
  create = false

  vpc_name = "unused"
}
```

### Public Topology (No NAT Gateways)

```hcl
module "networking" {
  source = "../../modules/aws/networking"

  vpc_name            = "vpc-dev-use1"
  address_space       = ["10.50.0.0/16"]
  create_nat_gateways = false

  subnets = {
    "public-a" = {
      address_prefixes  = ["10.50.0.0/24"]
      availability_zone = "us-east-1a"
      public            = true
    }
  }

  tags = {
    Environment = "dev"
  }
}
```

### Airgapped Topology

```hcl
module "networking" {
  source = "../../modules/aws/networking"

  vpc_name                = "vpc-airgapped-use1"
  address_space           = ["10.60.0.0/16"]
  create_internet_gateway = false
  create_nat_gateways     = false

  subnets = {
    "private-a" = {
      address_prefixes  = ["10.60.0.0/24"]
      availability_zone = "us-east-1a"
    }
  }

  interface_vpc_endpoints = ["secretsmanager", "ssm", "ssmmessages", "ec2messages", "sts", "kms"]

  tags = {
    Environment = "prod"
  }
}
```

### Single NAT Gateway (Cost Savings)

```hcl
module "networking" {
  source = "../../modules/aws/networking"

  vpc_name           = "vpc-preprod-use1"
  address_space      = ["10.200.0.0/16"]
  single_nat_gateway = true

  subnets = {
    "public-a" = {
      address_prefixes  = ["10.200.0.0/24"]
      availability_zone = "us-east-1a"
      public            = true
    }
    "private-a" = {
      address_prefixes  = ["10.200.10.0/24"]
      availability_zone = "us-east-1a"
    }
    "private-b" = {
      address_prefixes  = ["10.200.11.0/24"]
      availability_zone = "us-east-1b"
    }
  }

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
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_log](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.vpc_endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.eks_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.eks_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_ipv4_cidr_block_association.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | Name of the VPC to create | `string` | n/a | yes |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | CIDR blocks for the VPC | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_internet_gateway"></a> [create\_internet\_gateway](#input\_create\_internet\_gateway) | Create an internet gateway. Set false for airgapped environments. | `bool` | `true` | no |
| <a name="input_create_nat_gateways"></a> [create\_nat\_gateways](#input\_create\_nat\_gateways) | Create NAT gateways for private subnet internet egress. Set false for public or airgapped topologies. | `bool` | `true` | no |
| <a name="input_eks_cluster_name"></a> [eks\_cluster\_name](#input\_eks\_cluster\_name) | Name of the EKS cluster. Used for subnet tagging when enable\_eks\_networking is true. | `string` | `null` | no |
| <a name="input_enable_eks_networking"></a> [enable\_eks\_networking](#input\_enable\_eks\_networking) | Whether to enable EKS-specific networking features (security groups, subnet tags) | `bool` | `false` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Enable VPC Flow Logs | `bool` | `true` | no |
| <a name="input_flow_log_destination"></a> [flow\_log\_destination](#input\_flow\_log\_destination) | Flow log destination: cloud-watch-logs or s3 | `string` | `"cloud-watch-logs"` | no |
| <a name="input_flow_log_retention_days"></a> [flow\_log\_retention\_days](#input\_flow\_log\_retention\_days) | CloudWatch log group retention in days (ignored when destination is s3) | `number` | `30` | no |
| <a name="input_flow_log_s3_bucket_arn"></a> [flow\_log\_s3\_bucket\_arn](#input\_flow\_log\_s3\_bucket\_arn) | S3 bucket ARN for flow logs (required when flow\_log\_destination is s3) | `string` | `null` | no |
| <a name="input_interface_vpc_endpoints"></a> [interface\_vpc\_endpoints](#input\_interface\_vpc\_endpoints) | List of AWS service short names for Interface VPC endpoints (e.g., secretsmanager, ssm, sts, kms) | `list(string)` | `[]` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Use a single NAT gateway instead of one per AZ. Ignored if create\_nat\_gateways is false. | `bool` | `false` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Map of subnet names to configuration | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    availability_zone = optional(string)<br/>    public            = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_eks_security_group_id"></a> [eks\_security\_group\_id](#output\_eks\_security\_group\_id) | The ID of the EKS security group if created |
| <a name="output_flow_log_group_name"></a> [flow\_log\_group\_name](#output\_flow\_log\_group\_name) | The CloudWatch log group name for VPC flow logs |
| <a name="output_flow_log_id"></a> [flow\_log\_id](#output\_flow\_log\_id) | The ID of the VPC flow log |
| <a name="output_interface_endpoint_ids"></a> [interface\_endpoint\_ids](#output\_interface\_endpoint\_ids) | Map of service name to Interface VPC endpoint ID |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | The ID of the internet gateway |
| <a name="output_kubernetes_subnet_id"></a> [kubernetes\_subnet\_id](#output\_kubernetes\_subnet\_id) | The ID of the first kubernetes subnet (for EKS node groups) |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | Map of public subnet names to NAT gateway IDs |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | The ID of the network (VPC ID) |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | The name of the network (VPC name) |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | Map of private subnet names to route table IDs |
| <a name="output_public_route_table_id"></a> [public\_route\_table\_id](#output\_public\_route\_table\_id) | The ID of the public route table |
| <a name="output_s3_endpoint_id"></a> [s3\_endpoint\_id](#output\_s3\_endpoint\_id) | The ID of the S3 gateway endpoint |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Map of subnet names to subnet IDs |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | The primary CIDR block of the VPC |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC (alias for network\_id) |
<!-- END_TF_DOCS -->

## Notes

- An S3 gateway endpoint is always created (free) to reduce NAT costs for S3 traffic.
- Subnets with names ending in `kubernetes` get EKS-specific tags (`kubernetes.io/role/internal-elb`). Public subnets get `kubernetes.io/role/elb` when EKS networking is enabled.
- Interface VPC endpoints are placed in one private subnet per AZ, preferring subnets with "endpoints" in their name.
- Flow logs default to CloudWatch Logs but can be sent to S3 by setting `flow_log_destination = "s3"` with `flow_log_s3_bucket_arn`.
- Secondary CIDR blocks can be added via `address_space` (list). The first element is the primary VPC CIDR; additional entries create `aws_vpc_ipv4_cidr_block_association` resources.

## Related ADRs

- ADR-015: CIDR Allocation Strategy
