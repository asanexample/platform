variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for the k6 CronJob + script ConfigMap (the shared observability namespace — targets + Mimir are intra-namespace, so no NetworkPolicy changes)."
  type        = string
  default     = "observability"
}

variable "schedule" {
  description = "CronJob schedule for the k6 checks."
  type        = string
  default     = "*/5 * * * *"
}

variable "mimir_remote_write_url" {
  description = "Mimir push endpoint k6 exports its metrics to (Prometheus remote_write)."
  type        = string
  default     = "http://mimir-gateway.observability.svc/api/v1/push"
}

variable "tenant_id" {
  description = "Tenant (X-Scope-OrgID) k6 metrics are written under in Mimir."
  type        = string
  default     = "platform"
}

variable "k6_image" {
  description = "k6 container image (pinned)."
  type        = string
  default     = "grafana/k6:0.55.0"
}

variable "tags" {
  description = "Tags sanitized into K8s labels."
  type        = map(string)
  default     = {}
}
