output "bucket_name" {
  description = "Name of the S3 state bucket."
  value       = try(aws_s3_bucket.state[0].id, null)
}

output "bucket_arn" {
  description = "ARN of the S3 state bucket."
  value       = try(aws_s3_bucket.state[0].arn, null)
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB lock table."
  value       = try(aws_dynamodb_table.locks[0].name, null)
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB lock table."
  value       = try(aws_dynamodb_table.locks[0].arn, null)
}
