output "gateway_name" {
  description = "Name of the Gateway resource"
  value       = local.create ? var.gateway_name : null
}

output "gateway_namespace" {
  description = "Namespace of the Gateway resource"
  value       = local.create ? var.gateway_namespace : null
}

output "cluster_issuer_name" {
  description = "Name of the ClusterIssuer"
  value       = local.create ? var.cluster_issuer_name : null
}

output "route_hostnames" {
  description = "Map of route names to their FQDNs"
  value       = local.create ? { for k, v in var.routes : k => "${k}.${var.domain}" } : {}
}
