output "helm_release_status" {
  description = "Status of the external-dns Helm release"
  value       = local.create ? helm_release.external_dns[0].status : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where external-dns is installed"
  value       = local.create ? helm_release.external_dns[0].namespace : var.namespace
}

output "role_arn" {
  description = "ARN of the external-dns IAM role (bound to the SA via EKS Pod Identity)"
  value       = local.create ? aws_iam_role.external_dns[0].arn : null
}
