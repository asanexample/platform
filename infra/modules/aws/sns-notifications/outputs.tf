output "topic_arn" {
  description = "ARN of the alerts SNS topic. Publishers grant themselves sns:Publish on this via their own IAM identity policy."
  value       = try(aws_sns_topic.this[0].arn, "")
}

output "topic_name" {
  description = "Name of the alerts SNS topic."
  value       = try(aws_sns_topic.this[0].name, "")
}
