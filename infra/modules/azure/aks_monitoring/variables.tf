/**
 * # AKS Monitoring Module - Variables
 *
 * This module configures monitoring for AKS clusters, including Log Analytics integration,
 * diagnostic settings, and Azure Monitor for Containers.
 */

# ---------------------------------------------------------------------------------------------------------------------
# NAMING AND GENERAL VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "prefix" {
  description = "The prefix to use for generated resource names"
  type        = string
  default     = "centric"
  validation {
    condition     = length(var.prefix) <= 10
    error_message = "The prefix can be at most 10 characters."
  }
}

variable "customer" {
  description = "The customer identifier"
  type        = string
  default     = "shared"
  validation {
    condition     = length(var.customer) <= 15
    error_message = "The customer identifier can be at most 15 characters."
  }
}

variable "stage" {
  description = "The environment stage (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "Stage must be one of: dev, test, staging, prod."
  }
}

variable "region_abbv" {
  description = "The abbreviated region name"
  type        = string
  default     = "weu"
}

# ---------------------------------------------------------------------------------------------------------------------
# RESOURCE GROUP AND LOCATION
# ---------------------------------------------------------------------------------------------------------------------

variable "resource_group_name" {
  description = "The resource group name where the monitoring resources will be created"
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "The Azure location where the monitoring resources will be deployed"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# CLUSTER INFORMATION
# ---------------------------------------------------------------------------------------------------------------------

variable "cluster_name" {
  description = "The name of the AKS cluster to be monitored"
  type        = string
}

variable "cluster_id" {
  description = "The ID of the AKS cluster to be monitored"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# DIAGNOSTIC SETTINGS
# ---------------------------------------------------------------------------------------------------------------------

variable "diagnostic_setting_name" {
  description = "The name of the diagnostic setting. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace for diagnostics and container insights"
  type        = string
}

variable "log_categories" {
  description = "The log categories to enable in the diagnostic setting"
  type        = list(string)
  default     = ["kube-apiserver", "kube-audit", "kube-audit-admin", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard"]
}

variable "metric_categories" {
  description = "The metric categories to enable in the diagnostic setting"
  type        = list(string)
  default     = ["AllMetrics"]
}

# ---------------------------------------------------------------------------------------------------------------------
# CONTAINER INSIGHTS
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_container_insights" {
  description = "Whether to enable Container Insights monitoring for the AKS cluster"
  type        = bool
  default     = true
}

variable "container_insights_dcr_name" {
  description = "The name of the Container Insights data collection rule. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "data_collection_interval" {
  description = "The interval at which data will be collected"
  type        = string
  default     = "PT1M"
}

variable "streaming_syslog_enabled" {
  description = "Whether to enable streaming of syslog data from the AKS cluster"
  type        = bool
  default     = true
}

variable "syslog_facilities" {
  description = "The syslog facilities to monitor"
  type        = list(string)
  default     = ["auth", "authpriv", "cron", "daemon", "kern", "syslog", "lpr", "mail", "mark", "news", "local0", "local1", "local2", "local3", "local4", "local5", "local6", "local7"]
}

variable "syslog_levels" {
  description = "The syslog levels to monitor"
  type        = list(string)
  default     = ["Debug", "Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
}

# ---------------------------------------------------------------------------------------------------------------------
# PROMETHEUS MONITORING
# ---------------------------------------------------------------------------------------------------------------------

variable "enable_prometheus" {
  description = "Whether to enable Prometheus monitoring for the AKS cluster"
  type        = bool
  default     = true
}

variable "prometheus_dcr_name" {
  description = "The name of the Prometheus data collection rule. If not provided, a name will be generated."
  type        = string
  default     = null
}

variable "prometheus_dce_name" {
  description = "The name of the Prometheus data collection endpoint. If not provided, a name will be generated."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------------------------------------------------
# TAGGING
# ---------------------------------------------------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
} 