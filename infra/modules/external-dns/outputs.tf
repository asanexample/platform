output "helm_release_status" {
  description = "Status of the external-dns Helm release"
  value       = local.create ? helm_release.external_dns[0].status : "disabled"
}

output "namespace" {
  description = "Kubernetes namespace where external-dns is installed"
  value       = local.create ? helm_release.external_dns[0].namespace : var.namespace
}

output "irsa_role_arn" {
  description = "ARN of the IRSA IAM role for external-dns"
  value       = local.create_irsa ? aws_iam_role.external_dns[0].arn : null
}
