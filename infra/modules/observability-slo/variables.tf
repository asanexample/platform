variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for the Sloth controller, the PrometheusServiceLevel CRs, and the SLO dashboards (the shared observability namespace — Sloth has no webhook, so the default-deny-ingress is fine)."
  type        = string
  default     = "observability"
}

variable "slo_engine" {
  description = "SLO engine. Only `sloth` is implemented (renders SLI recording + multi-window burn-rate alert rules from abstract {objective, window} specs). The seam for a future `pyrra`/`grafana_slo` swap (ADR-043 OSS-default/commercial opt-in)."
  type        = string
  default     = "sloth"
}

# ---------------------------------------------------------------------------
# SLO definitions (rendered into Sloth PrometheusServiceLevel CRs)
# ---------------------------------------------------------------------------

variable "slos" {
  description = <<-EOT
    Abstract SLO definitions. Each becomes a Sloth PrometheusServiceLevel; Sloth generates the SLI recording
    rules + multi-window burn-rate alerts. Queries use Sloth's `{{.window}}` placeholder (Sloth fills it per
    burn-rate window). Alerts route via the P4 Alertmanager by severity (pageAlert=critical, ticketAlert=warning).
  EOT
  type = list(object({
    name            = string # PrometheusServiceLevel name
    service         = string # SLO "service" label
    slo_name        = string # SLO id (e.g. "requests-availability")
    description     = string
    objective       = number                       # e.g. 99.9
    error_query     = string                       # event-error query, with {{.window}}
    total_query     = string                       # event-total query, with {{.window}}
    alert_name      = string                       # base alert name
    labels          = optional(map(string), {})    # extra labels on the SLO
    alert_labels    = optional(map(string), {})    # extra labels on the alerts
    page_severity   = optional(string, "critical") # fast-burn alert severity
    ticket_severity = optional(string, "warning")  # slow-burn alert severity
    runbook_url     = optional(string)             # applied to both page + ticket alert annotations
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Helm (Sloth controller)
# ---------------------------------------------------------------------------

variable "helm_repository" {
  description = "Sloth Helm repository."
  type        = string
  default     = "https://slok.github.io/sloth"
}

variable "helm_chart_version" {
  description = "sloth chart version (pinned in _versions.hcl)."
  type        = string
  default     = "0.16.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds)."
  type        = number
  default     = 300
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Dashboards
# ---------------------------------------------------------------------------

variable "slo_dashboard_datasource_uid" {
  description = "Grafana datasource uid the Sloth SLO dashboards query (the hub Mimir, where the SLI/burn-rate recording rules land via remote_write)."
  type        = string
  default     = "mimir"
}

variable "tags" {
  description = "Tags sanitized into K8s labels on the dashboard ConfigMaps."
  type        = map(string)
  default     = {}
}
