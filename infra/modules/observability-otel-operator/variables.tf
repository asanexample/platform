variable "create" {
  description = "Controls whether resources are created (cost_profile toggle — enable_instrumentation)."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for the operator + the platform Instrumentation CR. Its OWN namespace, NOT observability: observability's default-deny-ingress NetworkPolicy blocks the kube-apiserver from reaching the operator's mutating webhook (the API server isn't intra-namespace), which fails Instrumentation CR admission."
  type        = string
  default     = "opentelemetry-operator-system"
}

variable "instrumentation_name" {
  description = "Name of the platform Instrumentation CR. Apps opt in with annotation instrumentation.opentelemetry.io/inject-<lang>: \"<namespace>/<name>\"."
  type        = string
  default     = "platform"
}

variable "otlp_endpoint" {
  description = "OTLP endpoint injected into opted-in pods (the OpenTelemetry Collector gateway, P3b). Platform-managed, not app-wired (ADR-077 D2)."
  type        = string
  default     = "http://otel-collector.observability.svc:4318"
}

variable "sampler" {
  description = "Trace sampler for injected SDKs. dev = capture everything (low traffic); lower the ratio for busy clusters."
  type = object({
    type     = string
    argument = string
  })
  default = {
    type     = "parentbased_traceidratio"
    argument = "1.0"
  }
}

variable "helm_repository" {
  description = "OpenTelemetry Operator chart repository."
  type        = string
  default     = "https://open-telemetry.github.io/opentelemetry-helm-charts"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "opentelemetry-operator"
}

variable "helm_chart_version" {
  description = "OpenTelemetry Operator chart version."
  type        = string
  default     = "0.116.0"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 600
}

variable "tags" {
  description = "Tags/labels to apply."
  type        = map(string)
  default     = {}
}
