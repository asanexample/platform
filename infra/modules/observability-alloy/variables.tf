variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy Alloy into. Defaults to the observability hub namespace (shares the default-deny NetworkPolicy isolation). Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

variable "loki_push_url" {
  description = "Loki push endpoint (gateway) Alloy ships logs to — e.g. the observability-loki module's push_endpoint output."
  type        = string
  default     = "http://loki-gateway.observability.svc/loki/api/v1/push"
}

variable "tenant_id" {
  description = "Tenant (X-Scope-OrgID) Alloy stamps on platform logs. The fallback tenant for system pods when per_team_tenant is on; the sole tenant when it's off."
  type        = string
  default     = "platform"
}

variable "per_team_tenant" {
  description = "P13 per-team log isolation (#590): derive each log stream's Loki tenant from the pod's Kyverno-injected `team` label (env-namespace pods) instead of a single static tenant; system pods fall back to `tenant_id`. This is the WRITE half — reads are enforced by the loki-tenant-proxy. For a spoke, requires the hub Loki ingest edge to pass the tenant through rather than force-stamp it (write-integrity hardened later by ingest mTLS). Off by default (unchanged single-tenant behaviour)."
  type        = bool
  default     = false
}

variable "emoji_log_annotations" {
  description = "Prefix each log line with a level emoji (🔥 error, ⚠️ warn, ℹ️ info, 🐛 debug) for readability in Explore/terminal views. Purely cosmetic — no label/cardinality impact. Off by default."
  type        = bool
  default     = false
}

variable "external_labels" {
  description = "Static labels stamped on every log stream (Alloy loki.write external_labels). For a spoke, set `{ cluster = \"preprod\" }` so the hub can isolate/break-out logs by cluster (#627), matching the metrics `externalLabels.cluster`. Empty = none."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also fullnameOverride + the ServiceAccount name)."
  type        = string
  default     = "alloy"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "alloy"
}

variable "helm_chart_version" {
  description = "grafana/alloy chart version (pinned in _versions.hcl; resolved latest stable at authoring)."
  type        = string
  default     = "1.10.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds). A DaemonSet rolls out quickly; no PVCs."
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags sanitized into K8s labels (Alloy creates no AWS resources)."
  type        = map(string)
  default     = {}
}
