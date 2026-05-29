/**
 * # vCluster Module Variables
 */

variable "create" {
  description = "Controls whether vCluster resources should be created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name for the vCluster instance"
  type        = string
}

variable "namespace" {
  description = "Host cluster namespace to deploy the vCluster into"
  type        = string
}

variable "chart_version" {
  description = "Version of the vCluster Helm chart"
  type        = string
  default     = "0.34.1"
}

variable "vcluster_version" {
  description = "vCluster application version"
  type        = string
  default     = "0.34.1"
}

variable "values" {
  description = "Custom Helm values YAML to pass to the vCluster chart"
  type        = string
  default     = ""
}

variable "resource_limits" {
  description = "Resource limits for the vCluster control plane container"
  type = object({
    cpu    = string
    memory = string
  })
  default = null
}

variable "sync" {
  description = "Sync configuration for vCluster (controls which resources are synced between host and virtual cluster)"
  type = object({
    nodes           = optional(bool, false)
    ingresses       = optional(bool, false)
    storage_classes = optional(bool, false)
  })
  default = null
}

variable "policies" {
  description = "Policy enforcement for the vCluster deployment"
  type = object({
    network_policy = optional(bool, true)
    limit_range    = optional(bool, true)
    resource_quota = optional(bool, true)
  })
  default = {}
}

variable "persistence_enabled" {
  description = "Enable persistent volume for vCluster data (requires a working StorageClass + CSI driver)"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "StorageClass for vCluster persistent volume"
  type        = string
  default     = null
}

variable "custom_resource_sync" {
  description = "Custom resources to sync from virtual to host cluster (plural.apiGroup format)"
  type = list(object({
    group   = string
    version = string
    plural  = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
