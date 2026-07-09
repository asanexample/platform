output "domain_name" {
  description = "CodeArtifact domain name"
  value       = local.create ? aws_codeartifact_domain.this[0].domain : null
}

output "domain_arn" {
  description = "CodeArtifact domain ARN"
  value       = local.create ? aws_codeartifact_domain.this[0].arn : null
}

output "domain_owner" {
  description = "AWS account ID that owns the domain (needed by consumers to construct repository endpoints)"
  value       = local.create ? aws_codeartifact_domain.this[0].owner : null
}

output "kms_key_arn" {
  description = "KMS key ARN encrypting the domain's assets"
  value       = local.domain_key_arn
}

output "store_repository_names" {
  description = "Map of store (upstream-proxy) repository names to their names"
  value       = { for k, v in aws_codeartifact_repository.store : k => v.repository }
}

output "repository_arns" {
  description = "Map of consumer repository names to their ARNs"
  value       = { for k, v in aws_codeartifact_repository.this : k => v.arn }
}
