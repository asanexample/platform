output "namespace" {
  description = "Keycloak namespace"
  value       = var.namespace
}

output "service_name" {
  description = "Keycloak Service name (gateway-config route backend)"
  value       = var.helm_release_name
}

output "service_port" {
  description = "Keycloak Service HTTP port (gateway-config route backend port)"
  value       = 80
}

output "issuer" {
  description = "OIDC issuer base URL (realms live at <issuer>/realms/<realm>)"
  value       = var.hostname_url
}
