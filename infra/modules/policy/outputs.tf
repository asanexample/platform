output "namespace" {
  description = "Kubernetes namespace where the Kyverno engine is installed"
  value       = local.create ? helm_release.kyverno[0].namespace : var.namespace
}

output "engine_status" {
  description = "Status of the Kyverno engine Helm release"
  value       = local.create ? helm_release.kyverno[0].status : "disabled"
}

output "policies_status" {
  description = "Status of the platform ClusterPolicies Helm release"
  value       = local.create ? helm_release.policies[0].status : "disabled"
}

output "validation_failure_action" {
  description = "Effective policy action (Audit or Enforce) for the deployed ClusterPolicies"
  value       = var.validation_failure_action
}

output "kyverno_ecr_role_arn" {
  description = "ARN of the Kyverno IRSA role for ECR signature reads (null when image verification is disabled)"
  value       = local.create_irsa ? aws_iam_role.kyverno_ecr[0].arn : null
}
