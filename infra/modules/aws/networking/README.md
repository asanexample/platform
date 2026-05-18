# AWS Networking Module

Creates an AWS VPC with subnets, internet gateway, NAT gateways, and route tables.

## Usage

```hcl
module "networking" {
  source = "../networking"

  create        = true
  vpc_name      = "vpc-platform-dev-use1"
  address_space = ["10.100.0.0/16"]
  environment   = "dev"
  workload      = "platform"
  region_abbv   = "use1"

  subnets = {
    "az1-public" = {
      address_prefixes  = ["10.100.0.0/24"]
      availability_zone = "us-east-1a"
      public            = true
    }
    "az1-kubernetes" = {
      address_prefixes  = ["10.100.10.0/24"]
      availability_zone = "us-east-1a"
    }
  }

  enable_eks_networking = true
  eks_cluster_name      = "eks-platform-dev-use1"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "networking" {
  source   = "../networking"
  create   = false
  vpc_name = ""
  environment = "dev"
  workload    = "platform"
  region_abbv = "use1"
}
```

### VPC without EKS networking

```hcl
module "networking" {
  source = "../networking"

  vpc_name      = "vpc-platform-dev-use1"
  address_space = ["10.100.0.0/16"]
  environment   = "dev"
  workload      = "platform"
  region_abbv   = "use1"

  subnets = {
    "az1-public" = {
      address_prefixes  = ["10.100.0.0/24"]
      availability_zone = "us-east-1a"
      public            = true
    }
    "az1-private" = {
      address_prefixes  = ["10.100.10.0/24"]
      availability_zone = "us-east-1a"
    }
  }

  tags = { Environment = "dev" }
}
```

## Cross-Cloud Interface

This module exposes cloud-agnostic outputs so downstream modules can consume networking regardless of provider.

| Output | Description |
|--------|-------------|
| `network_id` | VPC ID |
| `network_name` | VPC name tag |
| `subnet_ids` | Map of subnet name to subnet ID |
| `kubernetes_subnet_id` | First subnet matching `*kubernetes` |
| `create` | Whether resources were created |

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.eks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.eks_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.eks_self](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_ipv4_cidr_block_association.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Environment name (e.g. ops, dev, staging, prod) | `string` | n/a | yes |
| workload | Workload name for resources | `string` | n/a | yes |
| region_abbv | Abbreviated region name for resource naming | `string` | n/a | yes |
| vpc_name | Name of the VPC to create | `string` | n/a | yes |
| address_space | CIDR blocks for the VPC | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| eks_cluster_name | Name of the EKS cluster. Used for subnet tagging when enable_eks_networking is true. | `string` | `null` | no |
| enable_eks_networking | Whether to enable EKS-specific networking features (security groups, subnet tags) | `bool` | `false` | no |
| subnets | Map of subnet names to configuration | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    availability_zone = optional(string)<br/>    public            = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| eks_security_group_id | The ID of the EKS security group if created |
| internet_gateway_id | The ID of the internet gateway |
| kubernetes_subnet_id | The ID of the first kubernetes subnet (for EKS node groups) |
| nat_gateway_ids | Map of public subnet names to NAT gateway IDs |
| network_id | The ID of the network (VPC ID) |
| network_name | The name of the network (VPC name) |
| private_route_table_ids | Map of private subnet names to route table IDs |
| public_route_table_id | The ID of the public route table |
| subnet_ids | Map of subnet names to subnet IDs |
| vpc_cidr_block | The primary CIDR block of the VPC |
| vpc_id | The ID of the VPC (alias for network_id) |
<!-- END_TF_DOCS -->

## Dependencies

None — this is a foundational networking module.

## Notes

- Public subnets are tagged for EKS auto-discovery (`kubernetes.io/role/elb`) when `enable_eks_networking = true`.
- Private subnets ending in `kubernetes` are tagged with `kubernetes.io/role/internal-elb` for internal load balancer placement.
- One NAT gateway is created per public subnet; each private subnet routes through the NAT in its availability zone.
