output "helm_release_status" {
  description = "Status of the cert-manager Helm release"
  value       = local.create ? helm_release.cert_manager[0].status : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where cert-manager is installed"
  value       = local.create ? helm_release.cert_manager[0].namespace : var.namespace
}

output "role_arn" {
  description = "ARN of the cert-manager IAM role (bound to the SA via EKS Pod Identity)"
  value       = local.create ? aws_iam_role.cert_manager[0].arn : null
}
