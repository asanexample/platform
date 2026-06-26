output "namespace" {
  description = "Namespace the Argo Rollouts controller runs in."
  value       = var.namespace
}

output "status" {
  description = "Helm release status."
  value       = local.create ? helm_release.argo_rollouts[0].status : "absent"
}
