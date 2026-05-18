output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC identity provider"
  value       = try(aws_iam_openid_connect_provider.github[0].arn, "")
}

output "role_arn" {
  description = "ARN of the IAM role for GitHub Actions"
  value       = try(aws_iam_role.this[0].arn, "")
}

output "role_name" {
  description = "Name of the IAM role"
  value       = try(aws_iam_role.this[0].name, "")
}
