output "trail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = local.create ? aws_cloudtrail.this[0].arn : null
}

output "s3_bucket_id" {
  description = "ID of the S3 bucket storing CloudTrail logs"
  value       = local.create ? aws_s3_bucket.trail[0].id : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for CloudTrail events"
  value       = local.create && var.enable_cloudwatch ? aws_cloudwatch_log_group.trail[0].name : null
}
