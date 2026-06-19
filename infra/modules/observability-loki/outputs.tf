output "chunks_bucket_name" {
  description = "Name of the S3 bucket holding Loki chunks."
  value       = try(aws_s3_bucket.chunks[0].bucket, "")
}

output "loki_role_arn" {
  description = "Pod Identity role ARN the Loki ServiceAccount assumes for S3 access (empty when not created)."
  value       = try(aws_iam_role.loki[0].arn, "")
}

output "push_endpoint" {
  description = "In-cluster log push endpoint (gateway). Tenant via the X-Scope-OrgID header."
  value       = "http://${var.helm_release_name}-gateway.${var.namespace}.svc/loki/api/v1/push"
}

output "query_endpoint" {
  description = "In-cluster Loki query endpoint (gateway) for the Grafana datasource."
  value       = "http://${var.helm_release_name}-gateway.${var.namespace}.svc"
}
