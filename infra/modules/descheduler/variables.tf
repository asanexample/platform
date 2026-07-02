variable "create" {
  description = "Whether to create the descheduler release (false = no-op, for destroy ordering)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (for labelling / context only)."
  type        = string
}

variable "namespace" {
  description = "Namespace for the descheduler."
  type        = string
  default     = "kube-system"
}

variable "helm_chart_version" {
  description = "descheduler (kubernetes-sigs) Helm chart version (pinned in _versions.hcl)."
  type        = string
}

variable "helm_wait" {
  description = "Wait for the release to become ready before returning."
  type        = bool
  default     = true
}

variable "schedule" {
  description = "CronJob schedule for descheduler runs. Cadence trades responsiveness (rebalance sooner after node churn) against eviction churn; ~15 min is a calm default."
  type        = string
  default     = "*/15 * * * *"
}

# LowNodeUtilization: a node BELOW every underutilized threshold is a target to move pods TO; a node ABOVE any
# target threshold is overutilized and pods are evicted FROM it until it drops back under. The gap between the
# two must be wide enough that rebalancing doesn't ping-pong. Percentages of the node's allocatable.
variable "underutilized_thresholds" {
  description = "A node under ALL of these (percent of allocatable) is underutilized — a destination for evicted pods."
  type        = map(number)
  default     = { cpu = 40, memory = 40, pods = 40 }
}

variable "overutilized_thresholds" {
  description = "A node over ANY of these (percent of allocatable) is overutilized — pods are evicted from it. Post-unpark, one node routinely lands ~99% CPU while another sits ~40% (ADR-093)."
  type        = map(number)
  default     = { cpu = 70, memory = 70, pods = 70 }
}

variable "resources" {
  description = "Resource requests/limits for the descheduler pod (it runs briefly per CronJob tick)."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = {
    requests = { cpu = "100m", memory = "128Mi" }
    limits   = { memory = "256Mi" }
  }
}

variable "tags" {
  description = "Tags projected onto pod labels (RFC1123-sanitized)."
  type        = map(string)
  default     = {}
}
