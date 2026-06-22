variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (Pod Identity association + S3 bucket name prefix)."
  type        = string
}

variable "aws_region" {
  description = "AWS region (S3 bucket + the Tempo S3 endpoint)."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace to deploy Tempo into. Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

variable "force_destroy" {
  description = "Allow deleting the (non-empty) traces bucket on destroy. Dev convenience."
  type        = bool
  default     = false
}

variable "retention_period" {
  description = "Trace block retention (Tempo compactor block_retention). Traces are high-volume; the dev default is short."
  type        = string
  default     = "72h"
}

variable "loki_datasource_uid" {
  description = "Grafana UID of the Loki datasource, for the Tempo trace->logs (tracesToLogsV2) link."
  type        = string
  default     = "loki"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also fullnameOverride, the Service name, and the ServiceAccount name)."
  type        = string
  default     = "tempo"
}

variable "helm_repository" {
  description = "Helm repository URL. The Tempo charts moved to grafana-community/helm-charts (Jan 2026); the old grafana/helm-charts copy is deprecated/frozen."
  type        = string
  default     = "https://grafana-community.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name — tempo-distributed (one chart, sized by high_availability)."
  type        = string
  default     = "tempo-distributed"
}

variable "helm_chart_version" {
  description = "grafana-community/tempo-distributed chart version (pinned in _versions.hcl; latest stable at authoring — app v2.10.7)."
  type        = string
  default     = "2.25.5"
}

variable "high_availability" {
  description = "Sizing toggle (cost_profile). false = single replica per component, RF1, caches off (dev). true = RF3, zone-aware, multi-replica, caches on (prod HA)."
  type        = bool
  default     = false
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds)."
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready (a single monolith pod schedules fine)."
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "StorageClass for the Tempo WAL/local-blocks PVC."
  type        = string
  default     = "gp3"
}

variable "tags" {
  description = "Tags applied to AWS resources (and sanitized into K8s labels)."
  type        = map(string)
  default     = {}
}
