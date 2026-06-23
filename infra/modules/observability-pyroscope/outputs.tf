output "namespace" {
  description = "Namespace Pyroscope runs in."
  value       = var.namespace
}

output "query_url" {
  description = "In-cluster Pyroscope query endpoint (the Grafana datasource URL)."
  value       = "http://${var.helm_release_name}.${var.namespace}.svc:4040"
}

output "service_account_name" {
  description = "Pyroscope ServiceAccount (bound to the S3 Pod Identity role)."
  value       = local.sa_name
}

output "profiles_bucket" {
  description = "S3 bucket holding the profiles."
  value       = local.profiles_bucket
}
