variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (used for S3 bucket + IAM role naming + the Pod Identity association)."
  type        = string
}

variable "aws_region" {
  description = "AWS region (S3 bucket region)."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace to deploy Loki into. Defaults to the observability hub namespace so it shares Grafana's datasource sidecar and the existing default-deny NetworkPolicy isolation. Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

# ---------------------------------------------------------------------------
# S3 (chunks storage)
# ---------------------------------------------------------------------------

variable "force_destroy" {
  description = "Allow Terraform to delete the (non-empty) Loki chunks bucket on destroy. true suits the rebuild-safe reference platform; set false to protect long-term logs."
  type        = bool
  default     = true
}

variable "retention_period" {
  description = "Loki per-tenant log retention (limits_config.retention_period), enforced by the compactor. Default 14d (336h)."
  type        = string
  default     = "336h"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name. Also used as fullnameOverride + the ServiceAccount name, so Service names are deterministic (e.g. <name>-gateway)."
  type        = string
  default     = "loki"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "loki"
}

variable "helm_chart_version" {
  description = "grafana/loki chart version (pinned in _versions.hcl; resolved latest stable at authoring)."
  type        = string
  default     = "7.0.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds). Generous: the StatefulSet binds a WaitForFirstConsumer PVC on first schedule."
  type        = number
  default     = 1200
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "high_availability" {
  description = "HA sizing: SimpleScalable (read/write/backend RF3) instead of the single-binary reference deployment, multi-replica gateway, memcached caches. false = single-binary minimal (reference cluster)."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass for the Loki PVC (WAL / local index scratch)."
  type        = string
  default     = "gp3"
}

# ---------------------------------------------------------------------------
# Tenancy / limits (per-tenant limits double as the noisy-neighbor security control)
# ---------------------------------------------------------------------------

variable "default_tenant_id" {
  description = "Tenant ID (X-Scope-OrgID) the Grafana datasource queries with — the hub's own logs live here."
  type        = string
  default     = "platform"
}

variable "extra_tenant_datasources" {
  description = "Additional X-Scope-OrgID tenants to provision as Grafana datasources beyond default_tenant_id — e.g. [\"preprod\"] for the preprod logs spoke (#627). Each renders a `Loki (<tenant>)` datasource."
  type        = list(string)
  default     = []
}

variable "enable_federated_datasource" {
  description = "Provision a `Loki (all clusters)` datasource that queries ALL tenants at once (`X-Scope-OrgID: <default>|<extras…>`). Loki supports multi-tenant queries via the pipe-separated header natively — no server flag needed (unlike Mimir). Platform-admin overview lane (#626/#629). Off by default."
  type        = bool
  default     = false
}

variable "read_proxy_url" {
  description = "P13 read-isolation enforcement (#590), identical to the mimir module: when set, the Grafana Loki datasources point at the loki-tenant-proxy with `oauthPassThru` (SSO identity decides scope) instead of the gateway with a fixed `X-Scope-OrgID`, and the per-cluster bypass datasources are dropped (only `loki` + `loki-all` remain, both proxy-fronted). Empty = direct datasources (pre-P13)."
  type        = string
  default     = ""
}

variable "spoke_ingest_passthrough" {
  description = "P13 per-team logs (#590): when true, the spoke ingest HTTPRoute STOPS force-setting `X-Scope-OrgID` and passes the spoke-supplied (per-team) tenant through to Loki. Required so preprod's per-team Alloy re-tenant survives the hub edge. Trades the cross-tenant write-spoofing guard for per-team writes — a deferred tradeoff hardened later by ingest mTLS (#590 Phase-4 D-2). Off = force-stamp (default, safe)."
  type        = bool
  default     = false
}

variable "spoke_ingest" {
  description = <<-EOT
    Cross-cluster spoke LOG ingest via the shared Cilium Gateway (hub-and-spoke, #627). When `tenants` is
    non-empty this self-routes — per spoke — a write-only HTTPRoute at `<prefix>-logs.<domain>` that force-SETS
    `X-Scope-OrgID` to the mapped tenant (overwriting any client value — the cross-tenant spoofing guard) and
    matches only the Loki push path (`/loki/api/v1/push`), plus a CiliumNetworkPolicy admitting the Gateway
    Envoy's `ingress` identity to the Loki gateway. Empty `tenants` disables it. Auth = network isolation.
  EOT
  type = object({
    domain            = string
    gateway_name      = string
    gateway_namespace = string
    tenants           = map(string) # hostname-prefix => X-Scope-OrgID tenant
  })
  default = {
    domain            = ""
    gateway_name      = ""
    gateway_namespace = ""
    tenants           = {}
  }
}

variable "max_global_streams_per_user" {
  description = "Per-tenant active streams cap (cardinality / memory / cost control)."
  type        = number
  default     = 5000
}

variable "ingestion_rate_mb" {
  description = "Per-tenant sustained ingestion limit (MB/sec)."
  type        = number
  default     = 4
}

variable "ingestion_burst_size_mb" {
  description = "Per-tenant ingestion burst size (MB)."
  type        = number
  default     = 6
}

variable "tags" {
  description = "Tags applied to AWS resources (and sanitized into K8s labels)."
  type        = map(string)
  default     = {}
}
