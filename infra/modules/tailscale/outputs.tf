output "helm_release_status" {
  description = "Status of the Tailscale operator Helm release"
  value       = local.create ? helm_release.tailscale_operator[0].status : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where the Tailscale operator is installed"
  value       = local.create ? helm_release.tailscale_operator[0].namespace : var.namespace
}

output "connector_name" {
  description = "Name of the Tailscale Connector resource"
  value       = local.create && length(var.advertise_routes) > 0 ? kubernetes_manifest.connector[0].manifest.metadata.name : null
}
