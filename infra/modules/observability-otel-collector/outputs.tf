output "otlp_grpc_endpoint" {
  description = "OTLP/gRPC endpoint apps send traces to (this collector's service)."
  value       = "http://${var.helm_release_name}.${var.namespace}.svc:4317"
}

output "otlp_http_endpoint" {
  description = "OTLP/HTTP endpoint apps send traces to."
  value       = "http://${var.helm_release_name}.${var.namespace}.svc:4318"
}
