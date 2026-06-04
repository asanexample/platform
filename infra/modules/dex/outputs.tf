output "namespace" {
  description = "Dex namespace"
  value       = var.namespace
}

output "service_name" {
  description = "Dex Service name (gateway-config route backend)"
  value       = var.helm_release_name
}

output "service_port" {
  description = "Dex Service HTTP port (gateway-config route backend port)"
  value       = 5556
}

output "issuer" {
  description = "OIDC issuer URL"
  value       = var.dex_issuer
}
