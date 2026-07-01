variable "create" {
  description = "Controls whether resources are created (cost/policy-reporting toggle — enable_policy_reporting)."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy into (the shared observability namespace)."
  type        = string
  default     = "observability"
}

variable "create_dashboards" {
  description = "Ship the chart's bundled Grafana dashboards via the sidecar ConfigMap pattern. True on a cluster that runs Grafana (the hub); false on a spoke that only emits metrics for the hub's federated view to render."
  type        = bool
  default     = true
}

variable "helm_repository" {
  description = "policy-reporter chart repository."
  type        = string
  default     = "https://kyverno.github.io/policy-reporter"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "policy-reporter"
}

variable "helm_chart_version" {
  description = "policy-reporter chart version."
  type        = string
  default     = "3.7.4"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags/labels to apply."
  type        = map(string)
  default     = {}
}
