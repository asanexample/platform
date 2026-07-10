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
# Tenancy (multi-cluster — #628). Tempo multitenancy is ON so each cluster is a tenant, like Loki/Mimir.
# ---------------------------------------------------------------------------

variable "default_tenant_id" {
  description = "Tenant (X-Scope-OrgID) the default Tempo datasource queries with, and that the hub's own traces are written under."
  type        = string
  default     = "platform"
}

variable "enable_metrics_generator" {
  description = "Enable the Tempo metrics-generator (P6 / APM): derives RED span-metrics + a service graph from traces and remote_writes them to Mimir, per-tenant (X-Scope-OrgID preserved). Needs Mimir on. Off = no APM metrics."
  type        = bool
  default     = false
}

variable "mimir_remote_write_url" {
  description = "Mimir push endpoint the metrics-generator remote_writes RED/service-graph metrics to (in-cluster gateway). Per-tenant via remote_write_add_org_id_header."
  type        = string
  default     = "http://mimir-gateway.observability.svc/api/v1/push"
}

variable "extra_tenant_datasources" {
  description = "Additional X-Scope-OrgID tenants to provision as Grafana datasources — e.g. [\"preprod\"] for the preprod traces spoke (#628). Each renders a `Tempo (<tenant>)` datasource."
  type        = list(string)
  default     = []
}

variable "enable_federated_datasource" {
  description = "Provision a `Tempo (all clusters)` datasource querying ALL tenants at once (`X-Scope-OrgID: <default>|<extras…>`). Tempo supports multi-tenant queries via the pipe-separated header. Platform-admin overview lane (#629). Off by default."
  type        = bool
  default     = false
}

variable "enable_traces_to_profiles" {
  description = "Add the `tracesToProfilesV2` link to each Tempo datasource (P8b) — a span jumps to its CPU flame graph in the matching Pyroscope tenant datasource (`tempo`->`pyroscope`). Set when Pyroscope (the profiles store) is deployed."
  type        = bool
  default     = false
}

variable "federated_profiles_cluster" {
  description = "Which cluster's Pyroscope datasource the FEDERATED `tempo-all` datasource links profiles to. Pyroscope has no federated `-all` datasource (unlike Mimir/Tempo), so the all-clusters trace view must point at one cluster's profiles store — the spoke that runs the instrumented apps. Yields `pyroscope-<value>`."
  type        = string
  default     = "preprod"
}

variable "spoke_ingest" {
  description = <<-EOT
    Cross-cluster spoke TRACE ingest via the shared Cilium Gateway (#628). When `tenants` is non-empty this
    self-routes — per spoke — a write-only HTTPRoute at `<prefix>-traces.<domain>` that force-SETS
    `X-Scope-OrgID` to the mapped tenant (overwriting any client value) and matches only the OTLP/HTTP trace
    path (`/v1/traces`), plus a CiliumNetworkPolicy admitting the Gateway Envoy's `ingress` identity to the
    Tempo distributor. Empty `tenants` disables it. Auth = network isolation.
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
