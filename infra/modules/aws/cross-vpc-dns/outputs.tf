output "phz_zone_ids" {
  description = "Map of record name to private hosted zone ID"
  value       = { for k, v in aws_route53_zone.this : k => v.zone_id }
}

output "resolver_outbound_endpoint_id" {
  description = "Outbound resolver endpoint ID"
  value       = local.use_outbound ? aws_route53_resolver_endpoint.outbound[0].id : null
}

output "resolver_inbound_endpoint_id" {
  description = "Inbound resolver endpoint ID"
  value       = local.use_inbound ? aws_route53_resolver_endpoint.inbound[0].id : null
}

output "resolver_inbound_ips" {
  description = "Map of subnet ID to inbound endpoint IP (use as forwarding rule targets)"
  value = local.use_inbound ? {
    for ip in aws_route53_resolver_endpoint.inbound[0].ip_address : ip.subnet_id => ip.ip
  } : {}
}
