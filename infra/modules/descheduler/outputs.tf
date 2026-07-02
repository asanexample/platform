output "namespace" {
  description = "Namespace the descheduler runs in."
  value       = var.namespace
}

output "status" {
  description = "Helm release status."
  value       = local.create ? helm_release.descheduler[0].status : "absent"
}
