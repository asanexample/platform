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
  default     = "0.24.1"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
