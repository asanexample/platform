/**
 * # Cilium Module Outputs
 */

output "helm_release_status" {
  description = "Status of the Cilium Helm release"
  value       = var.create ? helm_release.cilium[0].status : "disabled"
}

output "helm_release_name" {
  description = "Name of the Cilium Helm release"
  value       = var.create ? helm_release.cilium[0].name : var.helm_release_name
}

output "helm_release_version" {
  description = "Version of the Cilium Helm chart deployed"
  value       = var.create ? helm_release.cilium[0].version : var.helm_chart_version
}

output "namespace" {
  description = "Kubernetes namespace where Cilium is installed"
  value       = var.create ? helm_release.cilium[0].namespace : var.namespace
}

output "cilium_values" {
  description = "The values used for the Cilium Helm chart"
  value       = local.cilium_values
  sensitive   = true
} 