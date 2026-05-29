variable "create" {
  description = "Whether to create tenant resources"
  type        = bool
  default     = true
}

variable "tenants" {
  description = "Map of tenant names to their configuration"
  type = map(object({
    mode = optional(string, "namespace")
    resource_quota = optional(object({
      cpu    = optional(string, "4")
      memory = optional(string, "8Gi")
      pods   = optional(number, 20)
      # Object/storage caps to prevent exhaustion of shared cluster capacity.
      services      = optional(number, 20)
      loadbalancers = optional(number, 0) # ingress is via the shared Gateway (ADR-017), not per-tenant NLBs
      pvcs          = optional(number, 10)
      storage       = optional(string, "50Gi") # total requested PVC storage
    }), {})
  }))
  default = {}
}

variable "gateway_namespace" {
  description = "Namespace where the Gateway resource lives (for NetworkPolicy allow rules)"
  type        = string
  default     = "default"
}


variable "environment" {
  description = "Environment name"
  type        = string
}

variable "region_abbv" {
  description = "Abbreviated region name"
  type        = string
}

variable "vcluster_chart_version" {
  description = "vCluster Helm chart version"
  type        = string
  default     = "0.34.1"
}

variable "vcluster_storage_class" {
  description = "StorageClass for vCluster persistent volume"
  type        = string
  default     = null
}

variable "vcluster_persistence_enabled" {
  description = "Enable persistent volume for vCluster data (requires a working StorageClass + CSI driver)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
