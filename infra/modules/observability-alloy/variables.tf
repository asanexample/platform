variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy Alloy into. Defaults to the observability hub namespace (shares the default-deny NetworkPolicy isolation). Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

variable "loki_push_url" {
  description = "Loki push endpoint (gateway) Alloy ships logs to — e.g. the observability-loki module's push_endpoint output."
  type        = string
  default     = "http://loki-gateway.observability.svc/loki/api/v1/push"
}

variable "tenant_id" {
  description = "Tenant (X-Scope-OrgID) Alloy stamps on platform logs. Per-team derivation from the namespace is P10."
  type        = string
  default     = "platform"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also fullnameOverride + the ServiceAccount name)."
  type        = string
  default     = "alloy"
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
  description = "grafana/alloy chart version (pinned in _versions.hcl; resolved latest stable at authoring)."
  type        = string
  default     = "1.10.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds). A DaemonSet rolls out quickly; no PVCs."
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags sanitized into K8s labels (Alloy creates no AWS resources)."
  type        = map(string)
  default     = {}
}
