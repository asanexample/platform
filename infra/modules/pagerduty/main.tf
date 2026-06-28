# PagerDuty on-call structure (ADR-084 Phase 2 foundation).
#
# This module provisions the on-call STRUCTURE — one schedule, escalation policy, service, and
# Alertmanager (Events API v2) integration per team — and publishes each team's integration key to
# AWS Secrets Manager for the in-cluster Alertmanager (via External Secrets) to consume.
#
# We LINK people, but PROVISION structure + membership. PagerDuty accounts are owned by the person and
# never created from git (no PII in git, ADR-084); membership is platform-provisioned. Today every
# schedule is seeded with the existing admin user (the bootstrap seam, see the schedule below) until
# the directory's external_identity(provider='pagerduty') exists, at which point a roster-derived
# membership connector replaces that single input with no change to this structure.

# ---------------------------------------------------------------------------------------------------
# Data sources — existing PagerDuty objects (referenced, never created)
# ---------------------------------------------------------------------------------------------------

# The bootstrap on-call user: the existing PagerDuty admin. Referenced by email, NOT created — no
# PagerDuty accounts are managed from git (ADR-084). It already has the mobile app enrolled, so pages
# push immediately.
data "pagerduty_user" "oncall" {
  email = var.bootstrap_oncall_email
}

# Events API v2 integration vendor for Prometheus Alertmanager. pagerduty_vendor matches the vendor by
# (partial) name against the PagerDuty vendor catalog; "Prometheus" resolves to the Prometheus vendor.
data "pagerduty_vendor" "prometheus" {
  name = "Prometheus"
}

# ---------------------------------------------------------------------------------------------------
# Per-team on-call structure
# ---------------------------------------------------------------------------------------------------

# Weekly on-call schedule, one per team.
#
# BOOTSTRAP MEMBERSHIP SEAM — `users` is seeded with the single existing admin user. This is the ONE
# input that changes when the identity bridge lands: once the directory holds
# external_identity(provider='pagerduty') for each person, the roster + directory-derived per-team
# membership connector (see README / the identity & access strategy) replaces this list with the
# team's real roster. The schedule/EP/service structure below does NOT change — only this list.
#
# Backed by the PagerDuty v3 Schedules API (pagerduty_schedulev2). The legacy pagerduty_schedule (v1
# API) is deprecated in provider 3.x and renders a "Legacy" badge in the PagerDuty UI; v2 drops it.
# v2 replaces v1's turn-based `layer` with an explicit `rotation`/`event` window keyed by an RFC-5545
# RRULE: our weekly turn (the old rotation_turn_length_seconds = 604800) maps to FREQ=WEEKLY over a
# 7-day window, and the single bootstrap user maps to one `member` under a rotating-member strategy.
#
# BOOTSTRAP MEMBERSHIP SEAM — the single `member` is seeded with the existing admin user. This is the
# ONE input that changes when the identity bridge lands: once the directory holds
# external_identity(provider='pagerduty') for each person, the roster + directory-derived per-team
# membership connector (see README / the identity & access strategy) replaces this with the team's
# real roster (a multi-member rotation). The schedule/EP/service structure below does NOT change.
resource "pagerduty_schedulev2" "team" {
  for_each = var.teams

  name      = "${each.key}-oncall"
  time_zone = "America/Los_Angeles"

  rotation {
    event {
      name            = "Weekly rotation"
      start_time      = "2025-01-01T00:00:00-08:00"
      end_time        = "2025-01-08T00:00:00-08:00" # 7-day continuous shift (was rotation_turn_length_seconds = 604800)
      effective_since = "2025-01-01T00:00:00-08:00"
      recurrence      = ["RRULE:FREQ=WEEKLY"]

      assignment_strategy {
        type = "rotating_member_assignment_strategy"

        member {
          type    = "user_member"
          user_id = data.pagerduty_user.oncall.id
        }
      }
    }
  }
}

# Escalation policy, one per team: page the team's schedule, re-notify after 15 minutes, loop twice.
resource "pagerduty_escalation_policy" "team" {
  for_each = var.teams

  name      = "${each.key}-escalation"
  num_loops = 2

  rule {
    escalation_delay_in_minutes = 15

    target {
      type = "schedule_reference"
      id   = pagerduty_schedulev2.team[each.key].id
    }
  }
}

# Service, one per team, backed by the team's escalation policy. alert_creation = create alerts AND
# incidents so Events API v2 deduplicated alerts roll up into incidents that page the schedule.
resource "pagerduty_service" "team" {
  for_each = var.teams

  name              = "${each.key}-service"
  escalation_policy = pagerduty_escalation_policy.team[each.key].id
  alert_creation    = "create_alerts_and_incidents"
}

# Events API v2 (Prometheus) integration, one per team's service. integration_key is the routing key
# Alertmanager uses to send events to this service.
resource "pagerduty_service_integration" "alertmanager" {
  for_each = var.teams

  name    = "${each.key}-alertmanager"
  service = pagerduty_service.team[each.key].id
  vendor  = data.pagerduty_vendor.prometheus.id
}

# ---------------------------------------------------------------------------------------------------
# Routing keys → AWS Secrets Manager
# ---------------------------------------------------------------------------------------------------

# Publish each team's integration (routing) key to Secrets Manager so the in-cluster Alertmanager can
# read it via External Secrets. Stored as JSON {"routingKey": "<key>"} — the shape the observability
# module's ExternalSecret expects (it reads the `routingKey` property).
resource "aws_secretsmanager_secret" "routing_key" {
  for_each = var.teams

  name = "platform/pagerduty/${each.key}-routing-key"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "routing_key" {
  for_each = var.teams

  secret_id     = aws_secretsmanager_secret.routing_key[each.key].id
  secret_string = jsonencode({ routingKey = pagerduty_service_integration.alertmanager[each.key].integration_key })
}
