output "helm_release_status" {
  description = "Status of the CloudNativePG operator Helm release"
  value       = local.create ? helm_release.cloudnative_pg[0].status : "disabled"
}

output "namespace" {
  description = "Namespace where the CloudNativePG operator is installed"
  value       = local.create ? helm_release.cloudnative_pg[0].namespace : var.namespace
}
