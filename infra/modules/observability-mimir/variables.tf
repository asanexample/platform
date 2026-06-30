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

variable "cluster_label" {
  description = "Clean `cluster` label for Mimir's own self-metrics (#630) — matches the hub's Prometheus externalLabels.cluster (e.g. `platform`) so they're attributed to the cluster they run on, not the chart's default (the release name `mimir`). Empty falls back to cluster_name."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Namespace to deploy Mimir into. Defaults to the observability hub namespace so Mimir shares Grafana's datasource sidecar and the existing default-deny NetworkPolicy isolation. The namespace must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

# ---------------------------------------------------------------------------
# IAM (EKS Pod Identity — ADR-047)
# ---------------------------------------------------------------------------

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

variable "extra_tenant_datasources" {
  description = "Additional X-Scope-OrgID tenants to provision as Grafana datasources beyond default_tenant_id — e.g. [\"preprod\"] for the preprod spoke (P10). Each renders a `Mimir (<tenant>)` datasource querying the in-cluster gateway with that tenant header. Read path only (Grafana is in-cluster); never the default."
  type        = list(string)
  default     = []
}

variable "enable_federated_datasource" {
  description = "Enable Mimir read-path tenant federation (#626) and provision a single `Mimir (all clusters)` datasource that queries ALL tenants at once (`X-Scope-OrgID: <default>|<extras…>`), so one panel can span clusters. Write-isolation is unaffected (each spoke still writes only its own tenant at the Gateway edge). This is the PLATFORM-ADMIN overview lane — per-team scoping is P13 (#590). Off by default."
  type        = bool
  default     = false
}

variable "enable_ruler" {
  description = "Enable the Mimir ruler (P4) — evaluates alerting rules against EACH tenant's metrics (incl. the spokes' remote-written data) and sends fired alerts to ruler_alertmanager_url, so a spoke (e.g. preprod) failure produces an alert that reaches the hub Alertmanager → the triage agent (ADR-082). Rules are loaded per-tenant into ruler_storage via mimirtool/the ruler API (the rules-sync). Hub only. Off by default."
  type        = bool
  default     = false
}

variable "ruler_alertmanager_url" {
  description = "Alertmanager the Mimir ruler posts fired alerts to (the hub kube-prometheus-stack Alertmanager). Only used when enable_ruler."
  type        = string
  default     = "http://kube-prometheus-stack-alertmanager.observability.svc:9093"
}

variable "ruler_tenants" {
  description = "Spoke tenants (X-Scope-OrgID) to load the curated ruler alert rules into — the rules-sync CronJob runs `mimirtool rules sync` per tenant so each spoke's remote-written metrics produce alerts (→ hub Alertmanager → triage agent). Empty = no sync Job. Only used when enable_ruler."
  type        = list(string)
  default     = []
}

variable "mimirtool_version" {
  description = "grafana/mimirtool image tag for the ruler rules-sync CronJob (match the Mimir app version)."
  type        = string
  default     = "3.0.4"
}

variable "ruler_rules_sync_schedule" {
  description = "Cron schedule for the ruler rules-sync (reconciles each tenant's ruler to the curated rules ConfigMap)."
  type        = string
  default     = "*/15 * * * *"
}

variable "app_slos" {
  description = <<-EOT
    Per-app SLOs (ADR-056 / per-app SLOs → W11 error-budget freeze). Each entry renders Sloth-style multi-window
    burn-rate rules into an `app-slos` Mimir ruler namespace, loaded into the ruler tenant by the rules-sync. The
    `error_query`/`total_query` use a `{{window}}` placeholder (Beyla RED metrics filtered to the app's namespace).
    Produces `slo:current_burn_rate:ratio{sloth_id=...}` per app (the metric the freeze gate queries) + page/ticket
    burn alerts → hub Alertmanager. Usually registry-derived in the unit from the prod XEnvironment claims.
  EOT
  type = list(object({
    id              = string # unique SLO id, e.g. "alpha-shop-prod-availability"
    service         = string # service label, e.g. "app-alpha-shop"
    slo_name        = string # e.g. "requests-availability"
    objective       = number # e.g. 99.9
    error_query     = string # PromQL numerator with {{window}}
    total_query     = string # PromQL denominator with {{window}}
    alert_name      = string # base alert name (CamelCase)
    page_severity   = optional(string, "critical")
    ticket_severity = optional(string, "warning")
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Cross-cluster spoke ingest (P10) — Gateway-API-native, no proxy
# ---------------------------------------------------------------------------

variable "spoke_ingest" {
  description = <<-EOT
    Cross-cluster spoke metrics ingest via the shared Cilium Gateway (hub-and-spoke, ADR-044 / #102 P10).
    When `tenants` is non-empty this self-routes — for each spoke — a write-only HTTPRoute on the shared
    Gateway at `<prefix>-mimir.<domain>` that:
      • force-SETS `X-Scope-OrgID` to the mapped tenant, overwriting any client value (the cross-tenant
        spoofing guard — a spoke physically cannot write to another tenant), and
      • matches `/api/v1/push` (write), and — for any prefix in `query_tenants` — ALSO `/prometheus` (read,
        opt-in; powers spoke-side metric-gated canary, ADR-056 W8c). The read rule force-sets the SAME tenant
        header, so a spoke can only ever query ITS OWN tenant — never the hub's or another spoke's data,
    plus a CiliumNetworkPolicy admitting the Gateway Envoy's reserved `ingress` identity to the Mimir gateway
    (the observability ns is default-deny). `domain`/`gateway_name`/`gateway_namespace` identify the shared
    Gateway. Empty `tenants` disables the edge. Auth = network isolation (internal NLB + TGW); mTLS is the
    documented P10.x hardening follow-up.
  EOT
  type = object({
    domain            = string
    gateway_name      = string
    gateway_namespace = string
    tenants           = map(string)               # hostname-prefix => X-Scope-OrgID tenant
    query_tenants     = optional(set(string), []) # prefixes that ALSO get a read (/prometheus) route (W8c)
  })
  default = {
    domain            = ""
    gateway_name      = ""
    gateway_namespace = ""
    tenants           = {}
    query_tenants     = []
  }
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

variable "max_label_names_per_series" {
  description = "Per-tenant cap on label names per series (Mimir default 30). Raised to admit Beyla's label-rich auto-instrumentation series (P7) — it stamps ~35+ k8s attributes, so the default silently discards its RED metrics."
  type        = number
  default     = 50
}

variable "max_global_exemplars_per_user" {
  description = "Per-tenant in-memory exemplar storage (Mimir default 0 = OFF, exemplars discarded). >0 enables it so the Tempo metrics-generator's span-metrics exemplars (and Prometheus exemplars) are stored — the metric→trace link for APM (P6)."
  type        = number
  default     = 100000
}

variable "tags" {
  description = "Tags applied to AWS resources (and sanitized into K8s labels)."
  type        = map(string)
  default     = {}
}

variable "query_consumer_namespaces" {
  description = "Namespaces admitted to the Mimir gateway's query API directly in-cluster (e.g. backstage for the ADR-091 Cost tab). The observability ns default-denies ingress, so this is the allow."
  type        = list(string)
  default     = []
}
