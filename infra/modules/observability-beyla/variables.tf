variable "create" {
  description = "Controls whether resources are created (cost_profile toggle — enable_instrumentation)."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy the Beyla DaemonSet into (the shared, privileged-PSA observability namespace)."
  type        = string
  default     = "observability"
}

variable "instrument_namespaces" {
  description = "Glob of Kubernetes namespaces whose workloads Beyla instruments (eBPF discovery; `k8s_namespace` is a glob, not a regex). The platform-cluster dogfood targets the human-facing HTTP services."
  type        = string
  default     = "{backstage,keycloak,argocd,observability}"
}

variable "otel_traces_endpoint" {
  description = "OTLP endpoint Beyla exports traces to (the OpenTelemetry Collector gateway, P3b). gRPC."
  type        = string
  default     = "http://otel-collector.observability.svc:4317"
}

variable "helm_repository" {
  description = "Beyla chart repository (grafana)."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "beyla"
}

variable "helm_chart_version" {
  description = "Beyla chart version."
  type        = string
  default     = "1.16.8"
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
