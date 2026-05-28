/**
 * # vCluster Module Variables
 */

# Installation control
variable "create" {
  description = "Controls whether vCluster resources should be created"
  type        = bool
  default     = true
}

# Environment variables
variable "workload" {
  description = "Workload identifier for resource naming"
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment name (e.g., dev, ops, prod)"
  type        = string
}

variable "region_abbv" {
  description = "Abbreviated name of the region (e.g., wus for westus, eus for eastus)"
  type        = string
}

# vCluster configuration
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
  default     = "0.24.1"
}

variable "vcluster_version" {
  description = "vCluster application version"
  type        = string
  default     = "0.24.1"
}

variable "values" {
  description = "Custom Helm values YAML to pass to the vCluster chart"
  type        = string
  default     = ""
}

# Resource limits
variable "resource_limits" {
  description = "Resource limits for the vCluster syncer container"
  type = object({
    cpu    = string
    memory = string
  })
  default = null
}

# Sync configuration
variable "sync" {
  description = "Sync configuration for vCluster (controls which resources are synced between host and virtual cluster)"
  type = object({
    nodes           = optional(bool, false)
    ingresses       = optional(bool, true)
    storage_classes = optional(bool, false)
  })
  default = null
}

# Isolation settings
variable "isolation" {
  description = "Isolation settings for the vCluster"
  type = object({
    network_policy = optional(bool, true)
    limit_range = optional(object({
      enabled = optional(bool, true)
    }), null)
    resource_quota = optional(object({
      enabled = optional(bool, true)
    }), null)
  })
  default = null
}

# Ingress configuration
variable "ingress" {
  description = "Ingress configuration for vCluster API server exposure"
  type = object({
    enabled       = optional(bool, false)
    host          = optional(string, "")
    ingress_class = optional(string, "")
    tls_secret    = optional(string, "")
  })
  default = null
}

# Storage
variable "storage_class" {
  description = "Storage class for vCluster persistence"
  type        = string
  default     = null
}

# Generic resource sync (vCluster v0.24+)
variable "custom_resource_sync" {
  description = "Custom resources to sync from virtual to host cluster"
  type = list(object({
    group   = string
    version = string
    kind    = string
  }))
  default = []
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
