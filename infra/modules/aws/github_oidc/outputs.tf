output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider"
  value       = try(aws_iam_openid_connect_provider.github[0].arn, "")
}

output "role_arns" {
  description = "Map of role name to IAM role ARN"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "role_names" {
  description = "Map of role name to IAM role name"
  value       = { for k, r in aws_iam_role.this : k => r.name }
}
