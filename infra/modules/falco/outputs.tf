output "namespace" {
  description = "Namespace Falco is deployed into"
  value       = var.namespace
}

output "helm_release_status" {
  description = "Status of the Falco Helm release"
  value       = local.create ? helm_release.falco[0].status : null
}
