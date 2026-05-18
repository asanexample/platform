# ---------------------------------------------------------------------------
# Cross-cloud interface outputs
# These names mirror the Azure networking module for multi-cloud abstraction.
# ---------------------------------------------------------------------------

output "network_id" {
  description = "The ID of the network (VPC ID)"
  value       = var.create ? aws_vpc.this[0].id : null
}

output "network_name" {
  description = "The name of the network (VPC name)"
  value       = var.create ? var.vpc_name : null
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value       = var.create ? { for k, v in aws_subnet.this : k => v.id } : {}
}

output "kubernetes_subnet_id" {
  description = "The ID of the first kubernetes subnet (for EKS node groups)"
  value = var.create && var.enable_eks_networking ? try(
    [for k, v in aws_subnet.this : v.id if can(regex("kubernetes$", k))][0],
    null
  ) : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}

# ---------------------------------------------------------------------------
# Cloud-specific outputs (AWS)
# ---------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the VPC (alias for network_id)"
  value       = var.create ? aws_vpc.this[0].id : null
}

output "vpc_cidr_block" {
  description = "The primary CIDR block of the VPC"
  value       = var.create ? aws_vpc.this[0].cidr_block : null
}

output "internet_gateway_id" {
  description = "The ID of the internet gateway"
  value       = var.create && var.create_internet_gateway ? aws_internet_gateway.this[0].id : null
}

output "nat_gateway_ids" {
  description = "Map of public subnet names to NAT gateway IDs"
  value       = var.create ? { for k, v in aws_nat_gateway.this : k => v.id } : {}
}

output "public_route_table_id" {
  description = "The ID of the public route table"
  value       = var.create && var.create_internet_gateway ? aws_route_table.public[0].id : null
}

output "private_route_table_ids" {
  description = "Map of private subnet names to route table IDs"
  value       = var.create ? { for k, v in aws_route_table.private : k => v.id } : {}
}

output "eks_security_group_id" {
  description = "The ID of the EKS security group if created"
  value       = var.create && var.enable_eks_networking ? try(aws_security_group.eks[0].id, null) : null
}

output "s3_endpoint_id" {
  description = "The ID of the S3 gateway endpoint"
  value       = var.create ? aws_vpc_endpoint.s3[0].id : null
}

output "flow_log_id" {
  description = "The ID of the VPC flow log"
  value       = var.create && var.enable_flow_logs ? aws_flow_log.this[0].id : null
}

output "flow_log_group_name" {
  description = "The CloudWatch log group name for VPC flow logs"
  value       = local.enable_cw_flow_logs ? aws_cloudwatch_log_group.flow_log[0].name : null
}
