output "instance_arn" {
  description = "The ARN of the IAM Identity Center instance."
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "The ID of the Identity Store."
  value       = local.identity_store_id
}

output "permission_set_arns" {
  description = "Map of permission set names to their ARNs."
  value       = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}

output "group_ids" {
  description = "Map of group names to their IDs."
  value       = { for k, v in aws_identitystore_group.this : k => v.group_id }
}

output "user_ids" {
  description = "Map of usernames to their IDs."
  value       = { for k, v in aws_identitystore_user.this : k => v.user_id }
}
