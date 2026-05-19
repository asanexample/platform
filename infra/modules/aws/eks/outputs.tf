output "cluster_id" {
  description = "The name/ID of the EKS cluster"
  value       = local.create ? aws_eks_cluster.this[0].id : null
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = local.create ? aws_eks_cluster.this[0].arn : null
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS API server"
  value       = local.create ? aws_eks_cluster.this[0].endpoint : null
}

output "cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = local.create ? aws_eks_cluster.this[0].certificate_authority[0].data : null
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = local.create ? aws_eks_cluster.this[0].version : null
}

output "cluster_security_group_id" {
  description = "The EKS-managed cluster security group ID (auto-created by EKS)"
  value       = local.create ? aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id : null
}

output "oidc_provider_arn" {
  description = "The ARN of the IAM OIDC provider for IRSA"
  value       = local.create ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "oidc_provider_url" {
  description = "The OIDC issuer URL (without https:// prefix) for IRSA trust policies"
  value       = local.create ? replace(aws_eks_cluster.this[0].identity[0].oidc[0].issuer, "https://", "") : null
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for secrets encryption"
  value       = local.create_kms ? aws_kms_key.eks[0].arn : null
}
