output "service_name" {
  description = "The oauth2-proxy Service name — point the gateway HTTPRoute at this (port 80 → 4180), NOT the upstream directly."
  value       = var.name
}

output "service_port" {
  description = "The oauth2-proxy Service port (the chart's default)."
  value       = 80
}
