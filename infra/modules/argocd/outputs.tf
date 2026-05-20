output "helm_release_status" {
  description = "Status of the ArgoCD Helm release"
  value       = local.create ? helm_release.argocd[0].status : "disabled"
}

output "helm_release_name" {
  description = "Name of the ArgoCD Helm release"
  value       = local.create ? helm_release.argocd[0].name : var.helm_release_name
}

output "helm_release_version" {
  description = "Version of the ArgoCD Helm chart deployed"
  value       = local.create ? helm_release.argocd[0].version : var.helm_chart_version
}

output "namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = local.create ? helm_release.argocd[0].namespace : var.namespace
}

output "irsa_role_arn" {
  description = "ARN of the IRSA IAM role for ArgoCD service accounts"
  value       = local.create_irsa ? aws_iam_role.argocd[0].arn : null
}
