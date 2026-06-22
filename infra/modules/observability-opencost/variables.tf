variable "create" {
  description = "Controls whether resources are created (cost_profile toggle — enable_cost_metrics)."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy into (the shared observability namespace)."
  type        = string
  default     = "observability"
}

variable "prometheus_service" {
  description = "In-cluster Prometheus service name OpenCost queries for allocation data."
  type        = string
  default     = "kube-prometheus-stack-prometheus"
}

variable "prometheus_namespace" {
  description = "Namespace of the in-cluster Prometheus service."
  type        = string
  default     = "observability"
}

variable "prometheus_port" {
  description = "Port of the in-cluster Prometheus service."
  type        = number
  default     = 9090
}

variable "helm_repository" {
  description = "OpenCost chart repository."
  type        = string
  default     = "https://opencost.github.io/opencost-helm-chart"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "opencost"
}

variable "helm_chart_version" {
  description = "OpenCost chart version."
  type        = string
  default     = "2.5.23"
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
