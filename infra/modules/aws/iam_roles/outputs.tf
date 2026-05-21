output "role_arns" {
  description = "Map of role name to ARN"
  value       = { for name, role in aws_iam_role.this : name => role.arn }
}

output "role_names" {
  description = "Map of role name to IAM role name"
  value       = { for name, role in aws_iam_role.this : name => role.name }
}
