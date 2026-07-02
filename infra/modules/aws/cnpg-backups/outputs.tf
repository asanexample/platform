output "bucket_name" {
  description = "The CNPG backup bucket name."
  value       = one(aws_s3_bucket.backups[*].bucket)
}

output "bucket_arn" {
  description = "The CNPG backup bucket ARN."
  value       = one(aws_s3_bucket.backups[*].arn)
}

output "role_arns" {
  description = "Per-cluster backup IAM role ARN, keyed by cluster name (referenced by each cluster's Barman ObjectStore)."
  value       = { for k, r in aws_iam_role.cluster : k => r.arn }
}

output "destination_paths" {
  description = "Per-cluster Barman destinationPath (s3://<bucket>/<cluster>), keyed by cluster name."
  value       = { for c in var.clusters : c.name => "s3://${var.bucket_name}/${c.name}" }
}
