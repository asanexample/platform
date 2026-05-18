/**
 * # Policy Module Outputs
 */

output "namespace" {
  description = "Kubernetes namespace where Kyverno is installed"
  value       = var.create ? helm_release.kyverno[0].namespace : var.namespace
}

output "helm_release_status" {
  description = "Status of the Kyverno Helm release"
  value       = var.create ? helm_release.kyverno[0].status : "disabled"
}

output "compliance_tier" {
  description = "Compliance tier this deployment enforces"
  value       = var.compliance_tier
}
