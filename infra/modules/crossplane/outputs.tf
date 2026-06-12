output "namespace" {
  description = "Namespace Crossplane and its providers run in."
  value       = var.namespace
}

output "provisioner_role_arn" {
  description = "ARN of the IAM role the AWS provider assumes (via EKS Pod Identity) to provision environment resources. Null when no AWS providers are installed (e.g. a K8s-only workload cluster)."
  value       = local.enable_aws ? aws_iam_role.provisioner[0].arn : null
}

output "provider_service_account" {
  description = "ServiceAccount the provider pods run as (target of the Pod Identity association)."
  value       = var.provider_service_account
}

output "providerconfig_name" {
  description = "ProviderConfig name managed resources reference by default."
  value       = var.providerconfig_name
}
