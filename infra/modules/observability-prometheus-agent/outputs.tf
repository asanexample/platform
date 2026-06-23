output "namespace" {
  description = "Namespace the spoke agent runs in."
  value       = try(kubernetes_namespace_v1.this[0].metadata[0].name, var.namespace)
}

output "cluster_label" {
  description = "The `cluster` external label this spoke stamps on every series (the hub queries by it)."
  value       = local.cluster_label
}

output "remote_write_url" {
  description = "Hub Mimir endpoint the agent ships to (empty = remote_write disabled)."
  value       = var.remote_write_url
}
