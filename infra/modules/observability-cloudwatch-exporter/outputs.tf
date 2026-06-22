output "role_arn" {
  description = "IAM role ARN YACE assumes via Pod Identity (CloudWatch read)."
  value       = local.create ? aws_iam_role.this[0].arn : null
}

output "service_account" {
  description = "ServiceAccount name bound to the Pod Identity association."
  value       = local.sa_name
}
