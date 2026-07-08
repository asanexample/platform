output "repository_urls" {
  description = "Map of repository names to their URLs"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "pull_through_cache_prefixes" {
  description = "Map of pull-through cache rule keys to their ECR repository prefix"
  value       = { for k, v in aws_ecr_pull_through_cache_rule.this : k => v.ecr_repository_prefix }
}
