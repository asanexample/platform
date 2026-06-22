output "traces_bucket_name" {
  description = "S3 bucket holding Tempo trace blocks (empty when not created)."
  value       = local.traces_bucket
}

output "tempo_role_arn" {
  description = "IAM role ARN bound to the Tempo ServiceAccount via Pod Identity (empty when not created)."
  value       = try(aws_iam_role.tempo[0].arn, "")
}

output "otlp_grpc_endpoint" {
  description = "OTLP/gRPC endpoint trace producers (the OTel collector) push to."
  value       = "http://${var.helm_release_name}.${var.namespace}.svc:4317"
}

output "query_endpoint" {
  description = "Tempo query API (the Grafana Tempo datasource)."
  value       = "http://${var.helm_release_name}.${var.namespace}.svc:3200"
}
