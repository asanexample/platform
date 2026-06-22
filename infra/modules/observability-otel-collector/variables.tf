variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy the collector into. Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

variable "tempo_otlp_endpoint" {
  description = "Tempo OTLP/gRPC endpoint (host:port, no scheme) the collector exports traces to — the Tempo distributor."
  type        = string
  default     = "tempo-distributor.observability.svc:4317"
}

variable "high_availability" {
  description = "Sizing toggle (cost_profile). false = 1 replica (dev). true = 2 replicas (gateway HA)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also fullnameOverride, the Service name, and the ServiceAccount name)."
  type        = string
  default     = "otel-collector"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://open-telemetry.github.io/opentelemetry-helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "opentelemetry-collector"
}

variable "helm_chart_version" {
  description = "opentelemetry-collector chart version (pinned in _versions.hcl; latest stable at authoring)."
  type        = string
  default     = "0.158.2"
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
  description = "Tags (the collector creates no AWS resources; informational)."
  type        = map(string)
  default     = {}
}
