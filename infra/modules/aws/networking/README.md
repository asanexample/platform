# AWS Networking Module

Creates an AWS VPC with subnets, internet gateway, NAT gateways, route tables, S3 gateway endpoint, and VPC flow logs. Supports three network topologies: private (default), public, and airgapped.

## Network Topologies

| Topology | IGW | NAT | Use case |
|----------|-----|-----|----------|
| **Private** (default) | Yes | Yes | Production workloads — nodes in private subnets, NAT for internet egress |
| **Public** | Yes | No | Dev/sandbox — nodes get public IPs directly, no NAT cost |
| **Airgapped** | No | No | Regulated/isolated — no internet access, requires VPC endpoints |

## Usage

### Private topology with single NAT (recommended for non-prod)

```hcl
module "networking" {
  source = "../networking"

  vpc_name      = "platform-use1-vpc"
  address_space = ["10.100.0.0/16"]
  environment   = "platform"
  workload      = "platform"
  region_abbv   = "use1"

  subnets = {
    "az1-kubernetes" = {
      address_prefixes  = ["10.100.0.0/26"]
      availability_zone = "us-east-1a"
    }
    "az1-public" = {
      address_prefixes  = ["10.100.0.224/28"]
      availability_zone = "us-east-1a"
      public            = true
    }
  }

  create_nat_gateways = true
  single_nat_gateway  = true

  enable_eks_networking = true
  eks_cluster_name      = "platform-use1-eks"

  enable_flow_logs        = true
  flow_log_retention_days = 30

  tags = {
    Environment = "platform"
    ManagedBy   = "Terragrunt"
  }
}
```

### Public topology (no NAT cost)

```hcl
module "networking" {
  source = "../networking"

  vpc_name            = "dev-use1-vpc"
  create_nat_gateways = false
  # kubernetes subnets marked public = true in network.hcl
  # ...
}
```

### Airgapped topology

```hcl
module "networking" {
  source = "../networking"

  vpc_name                = "regulated-use1-vpc"
  create_internet_gateway = false
  create_nat_gateways     = false
  # All subnets are private, VPC endpoints required for AWS API access
  # ...
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

## Resources

| Name | Type |
| ---- | ---- |
| `aws_vpc.this` | VPC |
| `aws_vpc_ipv4_cidr_block_association.secondary` | Secondary CIDR blocks |
| `aws_internet_gateway.this` | Internet gateway (when `create_internet_gateway = true`) |
| `aws_subnet.this` | Subnets |
| `aws_eip.nat` | Elastic IPs for NAT gateways |
| `aws_nat_gateway.this` | NAT gateways (when `create_nat_gateways = true`) |
| `aws_route_table.public` | Public route table |
| `aws_route_table.private` | Private route tables (one per private subnet) |
| `aws_route.public_internet` | Public internet route via IGW |
| `aws_route.private_nat` | Private NAT routes |
| `aws_route_table_association.public` | Public subnet route table associations |
| `aws_route_table_association.private` | Private subnet route table associations |
| `aws_vpc_endpoint.s3` | S3 gateway endpoint (free, always created) |
| `aws_security_group.eks` | EKS security group (when `enable_eks_networking = true`) |
| `aws_flow_log.this` | VPC flow log (when `enable_flow_logs = true`) |
| `aws_cloudwatch_log_group.flow_log` | Flow log CloudWatch log group |
| `aws_iam_role.flow_log` | Flow log IAM role |
| `aws_iam_role_policy.flow_log` | Flow log IAM policy |

## Inputs

| Name | Description | Type | Default |
| ---- | ----------- | ---- | ------- |
| `create` | Whether to create resources | `bool` | `true` |
| `vpc_name` | Name of the VPC | `string` | (required) |
| `address_space` | CIDR blocks for the VPC | `list(string)` | `["10.0.0.0/16"]` |
| `subnets` | Map of subnet names to configuration | `map(object)` | `{}` |
| `environment` | Environment name | `string` | (required) |
| `workload` | Workload identifier | `string` | (required) |
| `region_abbv` | Abbreviated region name | `string` | (required) |
| `tags` | Tags to apply to all resources | `map(string)` | `{}` |
| `create_internet_gateway` | Create an IGW (false for airgapped) | `bool` | `true` |
| `create_nat_gateways` | Create NAT gateways (false for public/airgapped) | `bool` | `true` |
| `single_nat_gateway` | Use one NAT gateway instead of per-AZ | `bool` | `false` |
| `enable_eks_networking` | Enable EKS subnet tags and security group | `bool` | `false` |
| `eks_cluster_name` | EKS cluster name for subnet tagging | `string` | `null` |
| `enable_flow_logs` | Enable VPC Flow Logs | `bool` | `true` |
| `flow_log_destination` | Flow log destination: `cloud-watch-logs` or `s3` | `string` | `"cloud-watch-logs"` |
| `flow_log_retention_days` | CloudWatch log group retention (ignored for S3) | `number` | `30` |
| `flow_log_s3_bucket_arn` | S3 bucket ARN (required when destination is `s3`) | `string` | `null` |

## Outputs

| Name | Description |
| ---- | ----------- |
| `network_id` / `vpc_id` | VPC ID |
| `network_name` | VPC name |
| `vpc_cidr_block` | Primary CIDR block |
| `subnet_ids` | Map of subnet names to IDs |
| `kubernetes_subnet_id` | First kubernetes subnet ID |
| `internet_gateway_id` | IGW ID (null if airgapped) |
| `nat_gateway_ids` | Map of NAT gateway IDs |
| `public_route_table_id` | Public route table ID |
| `private_route_table_ids` | Map of private route table IDs |
| `eks_security_group_id` | EKS security group ID |
| `s3_endpoint_id` | S3 gateway endpoint ID |
| `flow_log_id` | VPC flow log ID |
| `flow_log_group_name` | CloudWatch log group name |

## Dependencies

None — this is a foundational networking module.
