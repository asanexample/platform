output "bucket_name" {
  description = "Name of the agent-eval corpus S3 bucket."
  value       = try(aws_s3_bucket.corpus[0].bucket, "")
}

output "bucket_arn" {
  description = "ARN of the agent-eval corpus S3 bucket (for the agent's identity-based write grant)."
  value       = try(aws_s3_bucket.corpus[0].arn, "")
}

output "kms_key_arn" {
  description = "ARN of the corpus CMK (agents must be granted GenerateDataKey/Decrypt on it to write/read)."
  value       = try(aws_kms_key.corpus[0].arn, "")
}

output "kms_key_alias" {
  description = "Alias of the corpus CMK."
  value       = try(aws_kms_alias.corpus[0].name, "")
}
