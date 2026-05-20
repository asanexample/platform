output "helm_release_status" {
  description = "Status of the cert-manager Helm release"
  value       = local.create ? helm_release.cert_manager[0].status : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where cert-manager is installed"
  value       = local.create ? helm_release.cert_manager[0].namespace : var.namespace
}

output "irsa_role_arn" {
  description = "ARN of the IRSA IAM role for cert-manager"
  value       = local.create_irsa ? aws_iam_role.cert_manager[0].arn : null
}
