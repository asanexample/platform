variable "create" {
  description = "Controls whether resources are created (the P13 write-path re-tenant toggle — enable_per_team_tenants)."
  type        = bool
  default     = false
}

variable "namespace" {
  description = "Namespace to deploy into (the shared observability namespace)."
  type        = string
  default     = "observability"
}

variable "mimir_push_url" {
  description = "The Mimir distributor/gateway push endpoint cortex-tenant forwards to, e.g. http://mimir-gateway.observability.svc/api/v1/push. This is the SAME endpoint Prometheus writes to today — cortex-tenant simply inserts itself in front of it to split a write into per-tenant sub-writes."
  type        = string
}

variable "routing_label" {
  description = "The series label cortex-tenant reads to pick the tenant (config.tenant.label). A platform-controlled relabel on the Prometheus/agent write path sets this to the team-from-namespace; cortex-tenant routes on it and strips it (label_remove) so it is never stored. Must be a NORMAL label (not `__`-prefixed — Prometheus drops meta-labels before remote_write). Deliberately NOT `tenant`: Mimir/Loki emit their own meaningful `tenant` label on per-tenant self-metrics, and routing on that name clobbers it (the forced relabel would overwrite + strip it). `route_tenant` is collision-free."
  type        = string
  default     = "route_tenant"
}

variable "default_tenant" {
  description = "Tenant used for any series missing the routing label — platform-owned infra (kube-system, observability, …) that isn't a team. Fail-safe: never leave empty (an empty default makes cortex-tenant 400 unlabeled series, dropping infra metrics)."
  type        = string
  default     = "platform"
}

variable "replicas" {
  description = "cortex-tenant replicas. It is on the metrics write path, so run at least 2 for availability."
  type        = number
  default     = 2
}

variable "helm_repository" {
  description = "cortex-tenant chart repository."
  type        = string
  default     = "https://blind-oracle.github.io/cortex-tenant"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "cortex-tenant"
}

variable "helm_chart_version" {
  description = "cortex-tenant chart version."
  type        = string
  default     = "0.8.1"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 600
}

variable "create_service_monitor" {
  description = "Create a ServiceMonitor so cortex-tenant's own metrics (throughput, per-tenant errors) are scraped — important, it sits on the write path."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags/labels to apply."
  type        = map(string)
  default     = {}
}
