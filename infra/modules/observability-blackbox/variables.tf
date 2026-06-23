variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for the blackbox-exporter + the Probe CRs (the shared observability namespace)."
  type        = string
  default     = "observability"
}

variable "probe_targets" {
  description = "URLs to probe (HTTP/TLS). The hub Prometheus scrapes the blackbox-exporter per target (via the Probe CR) → probe_success / probe_http_status_code / probe_ssl_earliest_cert_expiry / probe_duration_seconds, labelled instance=<url>. Empty = no Probe CR."
  type        = list(string)
  default     = []
}

variable "gateway_service_name" {
  description = "Cilium Gateway LoadBalancer Service name (`cilium-gateway-<gateway-name>`). Its ClusterIP is injected as a hostAlias for the probe hostnames so the exporter reaches the Gateway Envoy DIRECTLY — bypassing the internal NLB (which a pod can't reliably hairpin to from inside the same cluster). The probe URLs stay the real hostnames, so TLS SNI + Host still verify against the real cert. Empty disables the hostAlias rewrite."
  type        = string
  default     = ""
}

variable "gateway_service_namespace" {
  description = "Namespace of the Cilium Gateway Service."
  type        = string
  default     = "default"
}

variable "probe_interval" {
  description = "Probe scrape interval."
  type        = string
  default     = "60s"
}

variable "probe_timeout" {
  description = "Per-probe HTTP timeout. 10s allows heavy apps (e.g. Backstage rendering its catalog) to respond without false-positive failures, while still catching genuine outages (connection refused, TLS errors, 5xx)."
  type        = string
  default     = "10s"
}

variable "valid_status_codes" {
  description = "HTTP status codes the probe treats as success (our endpoints redirect to login / require auth, so 3xx/401/403 are 'up', not down)."
  type        = list(number)
  default     = [200, 301, 302, 401, 403]
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "helm_chart_version" {
  description = "prometheus-blackbox-exporter chart version (pinned in _versions.hcl)."
  type        = string
  default     = "11.13.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds)."
  type        = number
  default     = 300
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags (informational; blackbox creates no AWS resources)."
  type        = map(string)
  default     = {}
}
