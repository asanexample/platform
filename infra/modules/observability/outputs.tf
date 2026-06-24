output "namespace" {
  description = "Observability namespace."
  value       = var.namespace
}

output "grafana_service_name" {
  description = "Grafana Service name (for the gateway HTTPRoute backend)."
  value       = "${var.helm_release_name}-grafana"
}

output "grafana_admin_secret_arn" {
  description = "Secrets Manager ARN holding the generated Grafana admin credential (retrieve to log in until SSO lands)."
  value       = try(aws_secretsmanager_secret.grafana_admin[0].arn, "")
}

output "alertmanager_role_arn" {
  description = "IAM role ARN bound to the Alertmanager SA via EKS Pod Identity for SNS publish (empty when no alerts topic)."
  value       = try(aws_iam_role.alertmanager[0].arn, "")
}
