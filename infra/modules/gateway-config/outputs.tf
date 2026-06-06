output "route_hostnames" {
  description = "Map of route names to their FQDNs"
  value       = local.create ? { for k, v in var.routes : k => "${k}.${var.domain}" } : {}
}
