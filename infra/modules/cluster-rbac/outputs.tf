output "cluster_role_name" {
  description = "Name of the platform-operator ClusterRole"
  value       = local.create ? kubernetes_cluster_role.platform_operator[0].metadata[0].name : null
}

output "group_name" {
  description = "Kubernetes group bound to the platform-operator ClusterRole"
  value       = var.group_name
}
