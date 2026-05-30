output "bucket_arns" {
  description = "Map of bucket name -> ARN"
  value       = { for k, b in aws_s3_bucket.this : k => b.arn }
}

output "bucket_ids" {
  description = "Map of bucket name -> ID (name)"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}
