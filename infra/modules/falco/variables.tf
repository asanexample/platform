variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "helm_chart_version" {
  description = "Version of the falcosecurity/falco Helm chart"
  type        = string
  default     = "9.0.0"
}

variable "helm_repository" {
  description = "Repository URL for the Falco Helm chart"
  type        = string
  default     = "https://falcosecurity.github.io/charts"
}

variable "namespace" {
  description = "Dedicated namespace for Falco (privileged eBPF DaemonSet — kept out of tenant/PSA-restricted namespaces)"
  type        = string
  default     = "falco"
}

variable "driver_kind" {
  description = "Falco driver. 'modern_ebpf' (CO-RE) needs kernel >= 5.8 and avoids any kernel-module/driver build — correct for the AL2023 6.x nodes and coexists with Cilium's eBPF."
  type        = string
  default     = "modern_ebpf"

  validation {
    condition     = contains(["modern_ebpf", "ebpf", "kmod"], var.driver_kind)
    error_message = "driver_kind must be one of: modern_ebpf, ebpf, kmod."
  }
}

variable "enable_falcosidekick" {
  description = "Deploy falcosidekick (the alert-routing sidecar). With no outputs configured it logs events to stdout (verifiable); SNS/Slack/observability routing is layered on later (#116)."
  type        = bool
  default     = true
}

variable "falcosidekick_config" {
  description = "Extra falcosidekick config (output destinations). Merged into the chart's falcosidekick.config — e.g. { sns = { topicarn = \"...\" } } once an SNS topic exists."
  type        = any
  default     = {}
}

variable "falco_resources" {
  description = "Resource requests/limits for the Falco DaemonSet container."
  type        = any
  default = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Whether to wait for the Helm release to become ready"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags/labels to apply (sanitized to RFC-1123 for K8s labels)"
  type        = map(string)
  default     = {}
}
