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

variable "dashboard_datasource_uid" {
  description = "Grafana datasource uid the cost dashboard queries (the Mimir where OpenCost metrics land). ADR-091."
  type        = string
  default     = "mimir"
}

variable "prometheus_external_url" {
  description = "External Prometheus-compatible query URL for OpenCost (e.g. the hub Mimir's query ingress, for a spoke with no in-cluster Prometheus). Empty = use the in-cluster prometheus_service. ADR-091."
  type        = string
  default     = ""
}

variable "create_dashboard" {
  description = "Create the Grafana cost dashboard ConfigMap. True on a cluster that runs Grafana (the hub); false on a spoke that only emits metrics. ADR-091."
  type        = bool
  default     = true
}

variable "enable_budget_enforcer" {
  description = "Run the budget-enforcement annotator (ADR-091 Phase C): an hourly CronJob that writes over-budget teams to the cost-budget-status ConfigMap the Kyverno policy reads. Enable on the spoke that runs OpenCost + the Team CRD (preprod)."
  type        = bool
  default     = false
}

variable "budget_enforcer_schedule" {
  description = "Cron schedule for the budget-enforcement annotator (ADR-091 Phase C). Cost is slow-moving — hourly is plenty."
  type        = string
  default     = "17 * * * *"
}

variable "budget_enforcer_image" {
  description = "Image for the budget-enforcement annotator (needs kubectl + curl + jq). ADR-091 Phase C."
  type        = string
  default     = "alpine/k8s:1.31.1"
}
