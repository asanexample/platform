variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace to deploy the collector into. Must already exist (created by the observability module)."
  type        = string
  default     = "observability"
}

variable "tempo_otlp_endpoint" {
  description = "Where the collector exports traces. HUB (gRPC): the in-cluster Tempo distributor `host:port` (no scheme). SPOKE (HTTP): the hub Tempo edge base URL `https://<spoke>-traces.<domain>` (the otlphttp exporter appends /v1/traces). Driven by exporter_use_http."
  type        = string
  default     = "tempo-distributor.observability.svc:4317"
}

variable "mimir_endpoint" {
  description = "Mimir Prometheus remote_write URL (e.g. the mimir module's push_endpoint, http://…-gateway…/api/v1/push). When set, the collector adds an OTLP→Mimir metrics pipeline; empty leaves it traces-only."
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Tenant (X-Scope-OrgID) stamped on the exported traces (Tempo multitenancy, #628). Hub = `platform`. For a spoke it's belt-and-suspenders — the hub Gateway edge force-overwrites it per-hostname."
  type        = string
  default     = "platform"
}

variable "exporter_use_http" {
  description = "false = OTLP/gRPC exporter to an in-cluster Tempo distributor (hub). true = OTLP/HTTP exporter to the hub Tempo edge over the Gateway (spoke), since the HTTPRoute terminates HTTP."
  type        = bool
  default     = false
}

variable "exporter_tls_insecure" {
  description = "TLS for the trace exporter. true = plaintext (in-cluster hub→Tempo). false = verify TLS (spoke→edge, public Let's Encrypt cert)."
  type        = bool
  default     = true
}

variable "resource_attributes" {
  description = "Resource attributes upserted on every span via a `resource` processor — e.g. { cluster = \"preprod\" } on a spoke so the hub can isolate/break-out traces by cluster (#628). Empty = no resource processor."
  type        = map(string)
  default     = {}
}

variable "high_availability" {
  description = "Sizing toggle (cost_profile). false = 1 replica (dev). true = 2 replicas (gateway HA)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also fullnameOverride, the Service name, and the ServiceAccount name)."
  type        = string
  default     = "otel-collector"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://open-telemetry.github.io/opentelemetry-helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "opentelemetry-collector"
}

variable "helm_chart_version" {
  description = "opentelemetry-collector chart version (pinned in _versions.hcl; latest stable at authoring)."
  type        = string
  default     = "0.158.2"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds)."
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags (the collector creates no AWS resources; informational)."
  type        = map(string)
  default     = {}
}
