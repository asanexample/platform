variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy into. Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

variable "loki_push_url" {
  description = "Loki push endpoint events are shipped to — the observability-loki module's push_endpoint."
  type        = string
  default     = "http://loki-gateway.observability.svc/loki/api/v1/push"
}

variable "tenant_id" {
  description = "Tenant (X-Scope-OrgID) stamped on event logs. Per-team derivation is P10."
  type        = string
  default     = "platform"
}

# ---------------------------------------------------------------------------
# Helm (grafana/alloy, reused as a singleton events watcher)
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also fullnameOverride + the ServiceAccount name)."
  type        = string
  default     = "alloy-events"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "alloy"
}

variable "helm_chart_version" {
  description = "grafana/alloy chart version (pinned in _versions.hcl)."
  type        = string
  default     = "1.10.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds)."
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags (no AWS resources; informational)."
  type        = map(string)
  default     = {}
}
