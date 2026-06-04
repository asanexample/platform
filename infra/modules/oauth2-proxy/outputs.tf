output "namespace" {
  description = "Namespace oauth2-proxy is deployed into"
  value       = var.namespace
}

output "service_name" {
  description = "oauth2-proxy Service name (gateway-config route backend)"
  value       = var.helm_release_name
}

output "service_port" {
  description = "oauth2-proxy Service port (gateway-config route backend port)"
  value       = var.service_port
}

output "pod_app_label" {
  description = "The app.kubernetes.io/name label of the proxy pods — used by the backstage chart NetworkPolicy ingressRules.podSelector to lock backstage:7007 to this proxy."
  value       = var.helm_release_name
}
