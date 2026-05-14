/**
 * # ArgoCD Module Outputs
 */

output "namespace" {
  description = "The namespace where ArgoCD is deployed"
  value       = var.namespace
}

output "release_name" {
  description = "The name of the Helm release"
  value       = helm_release.argocd.name
}

output "release_status" {
  description = "The status of the Helm release"
  value       = helm_release.argocd.status
}

output "version" {
  description = "The version of ArgoCD that was deployed"
  value       = var.chart_version
}

output "server_service_name" {
  description = "The name of the ArgoCD server service"
  value       = "${var.release_name}-server"
}

output "admin_password" {
  description = "The admin password for ArgoCD (only if explicitly set)"
  value       = var.admin_password != "" ? var.admin_password : "Password not provided by module. Check secret 'argocd-initial-admin-secret' in the ArgoCD namespace."
  sensitive   = true
} 