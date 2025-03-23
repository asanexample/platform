/**
 * # Container Insights DCR Variables
 *
 * Variables for the Container Insights DCR Module.
 */

variable "resource_group_name" {
  description = "The name of the resource group in which to create the DCR"
  type        = string
}

variable "location" {
  description = "The Azure region where the DCR should be created"
  type        = string
}

variable "cluster_name" {
  description = "The name of the AKS cluster"
  type        = string
}

variable "cluster_id" {
  description = "The ID of the AKS cluster"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for Container Insights"
  type        = string
}

variable "data_streams" {
  description = "The data streams to collect from the AKS cluster"
  type        = list(string)
  default     = ["Microsoft-ContainerLogV2", "Microsoft-Perf", "Microsoft-KubeEvents", "Microsoft-KubePodInventory", "Microsoft-KubeNodeInventory", "Microsoft-KubeServices", "Microsoft-KubePVInventory"]
}

variable "interval" {
  description = "The interval at which data is collected (e.g., '1m')"
  type        = string
  default     = "1m"
}

variable "namespace_filtering_mode" {
  description = "The namespace filtering mode (Include or Exclude)"
  type        = string
  default     = "Include"
}

variable "namespaces" {
  description = "The list of namespaces to include or exclude"
  type        = list(string)
  default     = ["kube-system"]
}

variable "enable_container_log_v2" {
  description = "Whether to enable the newer ContainerLogV2 format"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 