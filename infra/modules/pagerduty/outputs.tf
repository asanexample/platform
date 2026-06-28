output "teams" {
  description = "Per-team on-call objects, keyed by team name — the escalation-policy id (consumed by the ADR-084 Phase 2 triage agent's on-call paging), the service id, and the Secrets Manager secret name holding the Alertmanager routing key."
  value = {
    for t, _ in var.teams : t => {
      escalation_policy_id    = pagerduty_escalation_policy.team[t].id
      service_id              = pagerduty_service.team[t].id
      routing_key_secret_name = aws_secretsmanager_secret.routing_key[t].name
    }
  }
}

output "oncall_user_id" {
  description = "PagerDuty user id of the bootstrap on-call admin (the seeded schedule member)."
  value       = data.pagerduty_user.oncall.id
}
