variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Spoke EKS cluster name (resource naming / fallback cluster label)."
  type        = string
}

variable "cluster_label" {
  description = "Value of the `cluster` external label stamped on every series (so the hub can isolate this spoke, e.g. `up{cluster=\"preprod\"}`). Falls back to cluster_name when empty."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region (informational; the agent holds no AWS creds — it only scrapes + remote_writes)."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace to deploy the agent into. Created here (NOT by the chart) with PSA `privileged` (node-exporter needs host access) + a default-deny-ingress NetworkPolicy."
  type        = string
  default     = "observability"
}

# ---------------------------------------------------------------------------
# Remote write (the hub-and-spoke write path, #102 P10)
# ---------------------------------------------------------------------------

variable "remote_write_url" {
  description = "Hub Mimir spoke-ingest endpoint, e.g. https://preprod-mimir.aws.refplat.org/api/v1/push. The hub Gateway force-sets X-Scope-OrgID per-hostname, so the agent deliberately sends NO tenant header (it would be overwritten). Empty disables remote_write (agent buffers locally only)."
  type        = string
  default     = ""
}

variable "per_team_write_url" {
  description = "P13 per-team re-tenant (#590): the cortex-tenant ingest edge endpoint, e.g. https://preprod-tenant.aws.refplat.org/push. When set, the agent ADDITIONALLY remote_writes here with a forced namespace→route_tenant relabel, so cortex-tenant splits the spoke's metrics into per-team tenants — WITHOUT disturbing the primary force-stamped write to remote_write_url (the `preprod` tenant stays intact for the ruler/canary/cost consumers). Empty = single-write (unchanged)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also the chart fullname prefix)."
  type        = string
  default     = "prometheus-agent"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name. kube-prometheus-stack in agent mode — same chart as the hub, so metric names/labels match and the hub dashboards work for this spoke."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "helm_chart_version" {
  description = "kube-prometheus-stack chart version (pin from _versions.hcl; reuses the hub's pin)."
  type        = string
  default     = "87.5.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds). Generous: the Prometheus StatefulSet binds a WaitForFirstConsumer WAL PVC on first schedule."
  type        = number
  default     = 900
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "high_availability" {
  description = "HA sizing: 2 agent replicas + hard pod anti-affinity. false = single replica (reference spoke)."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass for the agent's remote-write WAL PVC (buffers samples across pod restarts during a hub outage). Empty string (default) = ephemeral emptyDir WAL — portable across clusters with no StorageClass dependency, which is the right default for a lightweight spoke. Set to a class that EXISTS on the spoke cluster (e.g. gp2/gp3) for a durable WAL."
  type        = string
  default     = ""
}

variable "wal_size" {
  description = "Size of the agent's WAL PVC (only used when storage_class is set)."
  type        = string
  default     = "5Gi"
}

variable "tags" {
  description = "Tags sanitized into K8s labels on the namespace."
  type        = map(string)
  default     = {}
}

variable "enable_team_budget_metric" {
  description = "Configure kube-state-metrics CustomResourceState to emit team_budget_monthly_usd{team} from the Team CR (ADR-091). Enable only on the spoke that runs the env-API Team CRD (preprod)."
  type        = bool
  default     = false
}

variable "enable_otlp_ingress" {
  description = "Add an ingress NetworkPolicy allowing OTLP (4317/4318) to the OTel collector from namespaces labeled platform.refplat.org/otel-export=true. Enable on spokes where tenant apps export traces via the OTel SDK (P14 log→trace). Off by default; the collector namespace otherwise default-denies cross-namespace ingress."
  type        = bool
  default     = false
}

variable "enable_crossplane_pod_monitor" {
  description = "Create a PodMonitor scraping the Crossplane core controller on THIS cluster (crossplane-system, app=crossplane, named `metrics` port) — mirrors the hub `observability` module's variable of the same name. Enable where crossplane + this spoke co-reside (e.g. preprod, where XEnvironment claims actually reconcile, ADR-048)."
  type        = bool
  default     = false
}

variable "enable_crossplane_provider_pod_monitor" {
  description = "Create a PodMonitor scraping Crossplane PROVIDER pods on THIS cluster (provider-aws-*, provider-family-aws, provider-kubernetes — any pod carrying `pkg.crossplane.io/provider`, named `metrics` port) — mirrors the hub `observability` module's variable of the same name. Covers composed-resource reconciliation, distinct from the core-controller PodMonitor above."
  type        = bool
  default     = false
}
