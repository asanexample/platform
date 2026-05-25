output "cluster_names" {
  description = "Names of registered remote clusters"
  value       = [for name, _ in kubernetes_secret_v1.cluster : name]
}
