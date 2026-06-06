output "gateway_name" {
  description = "Name of the Gateway resource (for app HTTPRoute parentRefs)."
  value       = local.create ? var.gateway_name : null
}

output "gateway_namespace" {
  description = "Namespace of the Gateway resource (for app HTTPRoute parentRefs)."
  value       = local.create ? var.gateway_namespace : null
}

output "cluster_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer."
  value       = local.create ? var.cluster_issuer_name : null
}
