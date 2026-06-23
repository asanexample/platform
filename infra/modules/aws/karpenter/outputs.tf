output "controller_role_arn" {
  description = "ARN of the Karpenter controller IAM role (Pod Identity)."
  value       = try(aws_iam_role.controller[0].arn, "")
}

output "interruption_queue_name" {
  description = "Name of the SQS interruption queue."
  value       = try(aws_sqs_queue.interruption[0].name, "")
}

output "namespace" {
  description = "Namespace the Karpenter controller runs in."
  value       = var.namespace
}
