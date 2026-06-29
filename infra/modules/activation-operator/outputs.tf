output "pod_identity_role_arn" {
  description = "ARN of the operator's Pod Identity role (the principal the management Identity Center admin role trusts)."
  value       = local.create ? aws_iam_role.operator[0].arn : null
}

output "namespace" {
  description = "Namespace the operator runs in."
  value       = var.namespace
}
