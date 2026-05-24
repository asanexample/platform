output "cluster_secret_store_name" {
  description = "Name of the Secrets Manager ClusterSecretStore"
  value       = local.create ? var.store_name : null
}

output "cluster_secret_store_ssm_name" {
  description = "Name of the SSM Parameter Store ClusterSecretStore"
  value       = local.create && var.create_ssm_store ? "${var.store_name}-ssm" : null
}
