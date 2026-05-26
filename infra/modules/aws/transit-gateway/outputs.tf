output "transit_gateway_id" {
  description = "The ID of the Transit Gateway"
  value       = local.create_tgw ? aws_ec2_transit_gateway.this[0].id : var.transit_gateway_id
}

output "transit_gateway_arn" {
  description = "The ARN of the Transit Gateway"
  value       = local.create_tgw ? aws_ec2_transit_gateway.this[0].arn : null
}

output "ram_share_arn" {
  description = "The ARN of the RAM resource share"
  value       = local.create_tgw && length(var.ram_share_principals) > 0 ? aws_ram_resource_share.this[0].arn : null
}

output "vpc_attachment_id" {
  description = "The ID of the VPC attachment"
  value       = local.create ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : null
}
