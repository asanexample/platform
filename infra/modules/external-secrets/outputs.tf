output "helm_release_status" {
  description = "Status of the external-secrets Helm release"
  value       = local.create ? helm_release.external_secrets[0].status : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where external-secrets is installed"
  value       = local.create ? helm_release.external_secrets[0].namespace : var.namespace
}

output "role_arn" {
  description = "ARN of the external-secrets IAM role (bound to the controller SA via EKS Pod Identity)"
  value       = local.create ? aws_iam_role.external_secrets[0].arn : null
}
