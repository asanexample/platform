output "role_arn" {
  description = "ARN of the triage-copilot agent IAM role"
  value       = local.create ? aws_iam_role.this[0].arn : null
}

output "role_name" {
  description = "Name of the triage-copilot agent IAM role"
  value       = local.create ? aws_iam_role.this[0].name : null
}
