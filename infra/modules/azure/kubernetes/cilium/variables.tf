/**
 * Variables for the Cilium CNI Installation Module
 */

variable "namespace" {
  description = "Kubernetes namespace where Cilium will be installed"
  type        = string
  default     = "kube-system"
}

variable "namespace_labels" {
  description = "Labels to apply to the Cilium namespace"
  type        = map(string)
  default     = {}
}

variable "chart_version" {
  description = "Version of the Cilium Helm chart to install"
  type        = string
  default     = "1.17.2"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 900
}

variable "wait" {
  description = "Whether to wait for the release to be deployed"
  type        = bool
  default     = true
}

variable "values_file" {
  description = "Path to a file containing custom Helm values"
  type        = string
  default     = ""
}

variable "values_content" {
  description = "Raw Helm values content"
  type        = string
  default     = ""
}

variable "set_values" {
  description = "Map of value pairs to pass to the Helm chart"
  type        = map(string)
  default     = {}
}

variable "kubernetes_host" {
  description = "Kubernetes API server host"
  type        = string
}

variable "kubernetes_port" {
  description = "Kubernetes API server port"
  type        = string
  default     = "443"
}

variable "operator_replicas" {
  description = "Number of replicas for Cilium operator"
  type        = string
  default     = "2"
}

variable "prometheus_enabled" {
  description = "Enable the Prometheus metrics in Cilium"
  type        = bool
  default     = true
}

variable "prometheus_service_monitor_enabled" {
  description = "Enable the Prometheus ServiceMonitor resources"
  type        = bool
  default     = false
} 