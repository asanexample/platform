variable "teams" {
  description = <<-EOT
    Teams to provision on-call structure for, keyed by team name (matches gitops/teams/<team>.yaml
    metadata.name). One schedule + escalation policy + service + Alertmanager integration is created
    per team. The value is intentionally minimal/empty today: team identity comes from the registry
    and there is nothing per-team to configure yet. It is a map (not a set) so that per-team knobs
    (e.g. an override time zone, or — once the directory lands — a derived roster) can be added later
    without a structural change at the call site.
  EOT
  type        = map(object({}))
}

variable "bootstrap_oncall_email" {
  description = <<-EOT
    Email of the EXISTING PagerDuty user placed on every team's schedule during bootstrap. This user
    is referenced (data source), never created — no PagerDuty accounts are managed from git (no PII in
    git; accounts are owned by the person and one-click-linked via OAuth, per ADR-084). This is the
    BOOTSTRAP membership seam: it is replaced — with zero structural change — by roster + directory
    -derived per-team membership once the directory's external_identity(provider='pagerduty') exists.
  EOT
  type        = string
}

variable "tags" {
  description = "Tags applied to the AWS Secrets Manager routing-key secrets."
  type        = map(string)
  default     = {}
}
