/**
 * # ArgoCD Bootstrap Module Outputs
 */

output "cert_manager_name" {
  description = "The name of the cert-manager application"
  value       = length(var.bootstrap_applications) > 0 ? kubernetes_manifest.cert_manager[0].manifest.metadata.name : ""
}

output "external_dns_name" {
  description = "The name of the external-dns application"
  value       = length(var.bootstrap_applications) > 0 ? kubernetes_manifest.external_dns[0].manifest.metadata.name : ""
}

output "external_secrets_name" {
  description = "The name of the external-secrets application"
  value       = length(var.bootstrap_applications) > 0 ? kubernetes_manifest.external_secrets[0].manifest.metadata.name : ""
}

output "bootstrap_applications_count" {
  description = "The number of bootstrap applications configured"
  value       = length(var.bootstrap_applications)
}

output "bootstrap_applications" {
  description = "The list of bootstrap applications"
  value       = var.bootstrap_applications
} 