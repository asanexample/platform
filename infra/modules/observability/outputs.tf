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
  description = "IRSA role ARN the Alertmanager SA assumes to publish to SNS (empty when no alerts topic)."
  value       = try(aws_iam_role.alertmanager[0].arn, "")
}
