output "query_url" {
  description = "In-cluster URL of the tenant-proxy (what the per-team Grafana datasource points at). Null when disabled."
  value       = var.create ? "http://tenant-proxy.${var.namespace}.svc:8080" : null
}
