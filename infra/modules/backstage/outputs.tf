output "namespace" {
  description = "Namespace where Backstage is deployed"
  value       = var.namespace
}

output "helm_release_status" {
  description = "Status of the Backstage Helm release"
  value       = local.create ? helm_release.backstage[0].status : "disabled"
}

output "service_name" {
  description = "Backstage Service name (HTTPRoute backend target)"
  value       = var.helm_release_name
}

output "service_port" {
  description = "Backstage Service port"
  value       = 7007
}

output "db_cluster_name" {
  description = "CloudNativePG Cluster name (in-cluster DB mode), else null"
  value       = local.in_cluster_db ? var.db_cluster_name : null
}
