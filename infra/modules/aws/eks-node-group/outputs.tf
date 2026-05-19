output "node_role_arn" {
  description = "The ARN of the IAM role used by node groups"
  value       = local.create ? aws_iam_role.node[0].arn : null
}

output "node_group_names" {
  description = "Map of node group names to their status"
  value       = var.create ? { for k, v in aws_eks_node_group.this : k => v.status } : {}
}
