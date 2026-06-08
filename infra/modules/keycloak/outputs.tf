output "namespace" {
  description = "Keycloak namespace"
  value       = var.namespace
}

output "service_name" {
  description = "Keycloak HTTP Service name (the keycloakx chart names it <release>-http; used as the port-forward / route backend)"
  value       = "${var.helm_release_name}-http"
}

output "service_port" {
  description = "Keycloak Service HTTP port (gateway-config route backend port)"
  value       = 80
}

output "issuer" {
  description = "OIDC issuer base URL (realms live at <issuer>/realms/<realm>)"
  value       = var.hostname_url
}
