output "blocks_bucket_name" {
  description = "Name of the S3 bucket holding Mimir blocks."
  value       = try(aws_s3_bucket.blocks[0].bucket, "")
}

output "mimir_role_arn" {
  description = "IRSA role ARN the Mimir ServiceAccount assumes for S3 access (empty when IRSA disabled)."
  value       = try(aws_iam_role.mimir[0].arn, "")
}

output "push_endpoint" {
  description = "In-cluster Prometheus remote_write endpoint (gateway). Tenant via the X-Scope-OrgID header."
  value       = "http://${var.helm_release_name}-gateway.${var.namespace}.svc/api/v1/push"
}

output "query_endpoint" {
  description = "In-cluster Prometheus-API query endpoint (gateway) for the Grafana datasource."
  value       = "http://${var.helm_release_name}-gateway.${var.namespace}.svc/prometheus"
}
