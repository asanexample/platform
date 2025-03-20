/**
 * Outputs for the Cilium CNI Installation Module
 * 
 * Note: The actual Helm installation has been removed from Terraform management.
 * These outputs provide placeholder values for compatibility with existing references.
 */

output "release_name" {
  description = "Name of the Helm release (placeholder)"
  value       = "cilium"
}

output "release_namespace" {
  description = "Namespace of the Helm release (placeholder)"
  value       = var.namespace
}

output "release_status" {
  description = "Status of the Helm release (placeholder)"
  value       = "external"
}

output "release_version" {
  description = "Version of the chart that was deployed (placeholder)"
  value       = var.chart_version
} 