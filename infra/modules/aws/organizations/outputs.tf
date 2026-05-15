output "organization_id" {
  description = "The ID of the AWS Organization."
  value       = try(aws_organizations_organization.this[0].id, data.aws_organizations_organization.current[0].id, null)
}

output "organization_arn" {
  description = "The ARN of the AWS Organization."
  value       = try(aws_organizations_organization.this[0].arn, data.aws_organizations_organization.current[0].arn, null)
}

output "root_id" {
  description = "The ID of the organization root."
  value       = local.root_id
}

output "ou_ids" {
  description = "Map of OU names to their IDs."
  value       = { for k, v in aws_organizations_organizational_unit.this : k => v.id }
}

output "ou_arns" {
  description = "Map of OU names to their ARNs."
  value       = { for k, v in aws_organizations_organizational_unit.this : k => v.arn }
}

output "account_ids" {
  description = "Map of account names to their IDs."
  value       = { for k, v in aws_organizations_account.this : k => v.id }
}

output "account_arns" {
  description = "Map of account names to their ARNs."
  value       = { for k, v in aws_organizations_account.this : k => v.arn }
}

output "scp_ids" {
  description = "Map of SCP names to their IDs."
  value       = { for k, v in aws_organizations_policy.this : k => v.id }
}
