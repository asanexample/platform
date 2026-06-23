variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace (the shared observability namespace — PSA privileged, so the eBPF DaemonSet runs)."
  type        = string
  default     = "observability"
}

variable "pyroscope_url" {
  description = "Pyroscope push endpoint Alloy writes profiles to."
  type        = string
  default     = "http://pyroscope.observability.svc:4040"
}

variable "tenant_id" {
  description = "Tenant (X-Scope-OrgID) profiles are written under in Pyroscope."
  type        = string
  default     = "platform"
}

# ---------------------------------------------------------------------------
# Helm (grafana/alloy)
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name."
  type        = string
  default     = "alloy-profiles"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart_version" {
  description = "grafana/alloy chart version (pinned in _versions.hcl)."
  type        = string
  default     = "1.10.0"
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

variable "tags" {
  description = "Tags (informational; this module creates no AWS resources)."
  type        = map(string)
  default     = {}
}
