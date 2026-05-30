output "association_arns" {
  description = "Map of association key -> association ARN"
  value       = { for k, a in aws_eks_pod_identity_association.this : k => a.association_arn }
}

output "association_ids" {
  description = "Map of association key -> association ID"
  value       = { for k, a in aws_eks_pod_identity_association.this : k => a.association_id }
}
