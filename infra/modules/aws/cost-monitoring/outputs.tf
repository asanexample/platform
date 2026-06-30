output "topic_arn" {
  description = "ARN of the cost-alerts SNS topic."
  value       = try(aws_sns_topic.cost_alerts[0].arn, null)
}

output "budget_names" {
  description = "Names of the created budgets."
  value       = sort([for b in aws_budgets_budget.this : b.name])
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Detection monitor."
  value       = try(aws_ce_anomaly_monitor.services[0].arn, null)
}

output "chatbot_configuration_arn" {
  description = "ARN of the AWS Chatbot Slack channel configuration (null when Slack delivery is disabled)."
  value       = try(aws_chatbot_slack_channel_configuration.cost[0].chat_configuration_arn, null)
}
