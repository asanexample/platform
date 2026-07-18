variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "prometheus-operator-crds Helm chart version. Pin to the release whose appVersion matches the kube-prometheus-stack operator version used by the observability stack (e.g. chart 30.0.1 = operator v0.92.1 = kube-prometheus-stack 87.5.0), so the CRD schemas match what the stack expects."
  type        = string
}
