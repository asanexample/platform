output "key_arn" {
  description = "ARN of the SOPS KMS key (for .sops.yaml creation rules)."
  value       = try(aws_kms_key.sops[0].arn, null)
}

output "key_id" {
  description = "Key ID of the SOPS KMS key."
  value       = try(aws_kms_key.sops[0].key_id, null)
}

output "alias_arn" {
  description = "ARN of the SOPS KMS alias."
  value       = try(aws_kms_alias.sops[0].arn, null)
}

output "alias_name" {
  description = "Alias name (with the alias/ prefix)."
  value       = try(aws_kms_alias.sops[0].name, null)
}
