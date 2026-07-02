# The in-cluster write endpoint Prometheus/the spoke agent should remote_write to INSTEAD of the
# Mimir gateway, once the per-team relabel is wired. The chart names the Service after the release.
output "write_url" {
  description = "cortex-tenant's remote_write ingest endpoint (point Prometheus/agent here to re-tenant by team). Null when the module is disabled."
  value       = var.create ? "http://cortex-tenant.${var.namespace}.svc:8080/push" : null
}
