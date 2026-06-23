variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace for Pyroscope (the shared observability namespace; the module does not create it)."
  type        = string
  default     = "observability"
}

variable "cluster_name" {
  description = "EKS cluster name (Pod Identity association + resource name prefixes)."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the S3 profiles bucket."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also the SA name + the in-cluster Service name → datasource URL)."
  type        = string
  default     = "pyroscope"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://grafana.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name."
  type        = string
  default     = "pyroscope"
}

variable "helm_chart_version" {
  description = "pyroscope chart version (pinned in _versions.hcl)."
  type        = string
  default     = "2.1.0"
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

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "storage_class" {
  description = "StorageClass for the Pyroscope PVC (local WAL + v2 metastore RAFT state; the durable store is S3)."
  type        = string
  default     = "gp3"
}

variable "persistence_size" {
  description = "Size of the Pyroscope data PVC."
  type        = string
  default     = "10Gi"
}

variable "force_destroy" {
  description = "Allow destroying the profiles bucket with objects in it (reference/dev convenience)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Multitenancy / datasources
# ---------------------------------------------------------------------------

variable "default_tenant_id" {
  description = "This cluster's tenant (X-Scope-OrgID) — the primary Pyroscope datasource header (`cluster == tenant == env`)."
  type        = string
  default     = "platform"
}

variable "extra_tenant_datasources" {
  description = "Additional tenants to render a `Pyroscope (<tenant>)` datasource for (e.g. spoke clusters). Same query endpoint, only the X-Scope-OrgID header differs."
  type        = list(string)
  default     = []
}

variable "spoke_ingest" {
  description = <<-EOT
    Cross-cluster spoke PROFILE ingest via the shared Cilium Gateway (hub-and-spoke, #629). When `tenants` is
    non-empty this self-routes — per spoke — a write-only HTTPRoute at `<prefix>-profiles.<domain>` that
    force-SETS `X-Scope-OrgID` to the mapped tenant (overwriting any client value — the cross-tenant spoofing
    guard) and matches only the Pyroscope push path, plus a CiliumNetworkPolicy admitting the Gateway Envoy's
    `ingress` identity to Pyroscope. Empty `tenants` disables it. Auth = network isolation.
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

variable "tags" {
  description = "AWS tags + sanitized into K8s labels on the datasource ConfigMap."
  type        = map(string)
  default     = {}
}
