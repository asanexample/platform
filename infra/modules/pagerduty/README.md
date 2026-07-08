# pagerduty

Provisions the PagerDuty **on-call structure** that backs ADR-084 Phase 2 (the triage agent paging
the owning team's on-call). Structure is in IaC; people are linked via the directory; rotation
membership is wired by a future connector.

## What it provisions

Per team (`for_each var.teams`, keyed by the team names from `gitops/teams/<team>.yaml`):

- `pagerduty_schedule` — a weekly rotation (v1 Schedules API). v1 is intentional for now: migrating to `pagerduty_schedulev2` (the v3 "flexible schedules" API) is blocked on an unresolved provider bug ([PagerDuty/terraform-provider-pagerduty#1127](https://github.com/PagerDuty/terraform-provider-pagerduty/issues/1127)) — the provider returns invalid objects on create against the early-access `/v3/schedules` endpoint, with no fix on the latest provider (3.33.0). The v1 resource emits a deprecation warning (expected, harmless); revisit when #1127 is resolved and v3 is GA.
- `pagerduty_escalation_policy` — re-notify after 15 min, loop twice, targeting the team's schedule.
- `pagerduty_service` — backed by the team's escalation policy (`create_alerts_and_incidents`).
- `pagerduty_service_integration` — an Events API v2 (Prometheus/Alertmanager) integration.
- `aws_secretsmanager_secret` (+ version) at `platform/pagerduty/<team>-routing-key`, holding
  `{"routingKey":"<integration-key>"}` for the in-cluster Alertmanager to read via External Secrets.

The on-call user is the **existing** PagerDuty admin (`var.bootstrap_oncall_email`), referenced via a
data source — **never created**. No PagerDuty accounts are managed from git (no PII in git; accounts
are owned by the person and one-click-linked via OAuth, per ADR-084).

The module declares **no provider block** — the live unit injects the `pagerduty` provider (token from
Secrets Manager) and the `aws` provider (from `root.hcl`).

## The bootstrap membership seam

Every schedule's `users` list is seeded today with the single bootstrap admin. This is the **one input
that changes** when the identity bridge lands. It is **not** a structural placeholder: once the
directory holds `external_identity(provider='pagerduty')` for each person, a roster-derived membership
connector (mirroring the Keycloak/GitHub generators) replaces this single input with each team's real
roster. The schedule / escalation policy / service structure does **not** change.

## Directory handoff dependency

The one interface to the identity workstream is the directory's `external_identity` rows where
`provider='pagerduty'` — `person ↔ PagerDuty user-id`. The identity workstream **populates** it
(Keycloak brokers PagerDuty as an OIDC IdP → directory sync upserts the link); the PagerDuty
membership connector and the triage agent's on-call resolver **read** it. See
`docs/architecture/pagerduty-identity-handoff.md`.

## Outputs

- `teams` — `{ team => { escalation_policy_id, service_id, routing_key_secret_name } }`
  (the escalation-policy ids feed the ADR-084 Phase 2 on-call paging).
- `oncall_user_id` — the bootstrap on-call user's PagerDuty id.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_pagerduty"></a> [pagerduty](#requirement\_pagerduty) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_pagerduty"></a> [pagerduty](#provider\_pagerduty) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.routing_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.routing_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [pagerduty_escalation_policy.team](https://registry.terraform.io/providers/PagerDuty/pagerduty/latest/docs/resources/escalation_policy) | resource |
| [pagerduty_schedule.team](https://registry.terraform.io/providers/PagerDuty/pagerduty/latest/docs/resources/schedule) | resource |
| [pagerduty_service.team](https://registry.terraform.io/providers/PagerDuty/pagerduty/latest/docs/resources/service) | resource |
| [pagerduty_service_integration.alertmanager](https://registry.terraform.io/providers/PagerDuty/pagerduty/latest/docs/resources/service_integration) | resource |
| [pagerduty_user.oncall](https://registry.terraform.io/providers/PagerDuty/pagerduty/latest/docs/data-sources/user) | data source |
| [pagerduty_vendor.prometheus](https://registry.terraform.io/providers/PagerDuty/pagerduty/latest/docs/data-sources/vendor) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_bootstrap_oncall_email"></a> [bootstrap\_oncall\_email](#input\_bootstrap\_oncall\_email) | Email of the EXISTING PagerDuty user placed on every team's schedule during bootstrap. This user<br/>is referenced (data source), never created — no PagerDuty accounts are managed from git (no PII in<br/>git; accounts are owned by the person and one-click-linked via OAuth, per ADR-084). This is the<br/>BOOTSTRAP membership seam: it is replaced — with zero structural change — by roster + directory<br/>-derived per-team membership once the directory's external\_identity(provider='pagerduty') exists. | `string` | n/a | yes |
| <a name="input_teams"></a> [teams](#input\_teams) | Teams to provision on-call structure for, keyed by team name (matches gitops/teams/<team>.yaml<br/>metadata.name). One schedule + escalation policy + service + Alertmanager integration is created<br/>per team. The value is intentionally minimal/empty today: team identity comes from the registry<br/>and there is nothing per-team to configure yet. It is a map (not a set) so that per-team knobs<br/>(e.g. an override time zone, or — once the directory lands — a derived roster) can be added later<br/>without a structural change at the call site. | `map(object({}))` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the AWS Secrets Manager routing-key secrets. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_oncall_user_id"></a> [oncall\_user\_id](#output\_oncall\_user\_id) | PagerDuty user id of the bootstrap on-call admin (the seeded schedule member). |
| <a name="output_teams"></a> [teams](#output\_teams) | Per-team on-call objects, keyed by team name — the escalation-policy id (consumed by the ADR-084 Phase 2 triage agent's on-call paging), the service id, and the Secrets Manager secret name holding the Alertmanager routing key. |
<!-- END_TF_DOCS -->