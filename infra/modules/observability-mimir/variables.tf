variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (used for S3 bucket + IAM role naming)."
  type        = string
}

variable "aws_region" {
  description = "AWS region (S3 endpoint + bucket region)."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace to deploy Mimir into. Defaults to the observability hub namespace so Mimir shares Grafana's datasource sidecar and the existing default-deny NetworkPolicy isolation. The namespace must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

# ---------------------------------------------------------------------------
# IRSA
# ---------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN for the Mimir IRSA trust policy. Empty string disables IRSA (the chart would then need static creds — not supported here)."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (no https:// prefix) for the IRSA trust policy."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# S3 (blocks storage)
# ---------------------------------------------------------------------------

variable "force_destroy" {
  description = "Allow Terraform to delete the (non-empty) Mimir blocks bucket on destroy. true suits the rebuild-safe reference platform; set false to protect long-term metrics."
  type        = bool
  default     = true
}

variable "blocks_retention" {
  description = "Mimir per-tenant blocks retention (compactor_blocks_retention_period). 0 = keep forever."
  type        = string
  default     = "365d"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name. Also used as fullnameOverride + the ServiceAccount name, so Service names are deterministic (e.g. <name>-gateway)."
  type        = string
  default     = "mimir"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "mimir-distributed"
}

variable "helm_chart_version" {
  description = "mimir-distributed chart version (6.0.x is the current stable line; 6.1.0-weekly tags are dev-only)."
  type        = string
  default     = "6.0.6"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds). Generous: the StatefulSets bind WaitForFirstConsumer PVCs on first schedule."
  type        = number
  default     = 1200
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "high_availability" {
  description = "HA sizing: RF3 + zone-aware ingester/store-gateway, multi-replica read/write path, memcached caches, query-scheduler, rollout-operator. false = single-replica minimal (reference cluster)."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass for the ingester/store-gateway/compactor PVCs (WAL/local blocks scratch)."
  type        = string
  default     = "gp3"
}

# ---------------------------------------------------------------------------
# Tenancy / limits (per-tenant limits double as the noisy-neighbor security control)
# ---------------------------------------------------------------------------

variable "default_tenant_id" {
  description = "Tenant ID (X-Scope-OrgID) the Grafana datasource queries with — the hub's own metrics live here."
  type        = string
  default     = "platform"
}

variable "datasource_is_default" {
  description = "Mark the provisioned Mimir Grafana datasource the default. Keep false until the kube-prometheus-stack Prometheus datasource is set non-default (avoids two Grafana defaults)."
  type        = bool
  default     = false
}

variable "max_global_series_per_user" {
  description = "Per-tenant active series cap (cardinality / memory / cost control)."
  type        = number
  default     = 1500000
}

variable "ingestion_rate" {
  description = "Per-tenant sustained samples/sec ingestion limit."
  type        = number
  default     = 100000
}

variable "ingestion_burst_size" {
  description = "Per-tenant ingestion burst size (samples)."
  type        = number
  default     = 200000
}

variable "tags" {
  description = "Tags applied to AWS resources (and sanitized into K8s labels)."
  type        = map(string)
  default     = {}
}
