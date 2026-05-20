/**
 * # Cilium Module Variables
 */

# Installation control
variable "create" {
  description = "Controls whether Cilium resources should be created"
  type        = bool
  default     = true
}

variable "cloud_provider" {
  description = "Cloud provider for platform-specific CNI config"
  type        = string
  default     = "azure"
  validation {
    condition     = contains(["azure", "aws", "gcp"], var.cloud_provider)
    error_message = "cloud_provider must be 'azure', 'aws', or 'gcp'"
  }
}

variable "k8s_service_host" {
  description = "Kubernetes API server hostname (required for BYOCNI — in-cluster service IP unreachable before CNI exists)"
  type        = string
  default     = ""
}

variable "k8s_service_port" {
  description = "Kubernetes API server port"
  type        = string
  default     = "443"
}

# Environment variables
variable "environment" {
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "workload" {
  description = "Workload identifier for resource naming"
  type        = string
  default     = "platform"
}

variable "region_abbv" {
  description = "Abbreviated name of the region (e.g., eus for eastus)"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the Azure resource group (only required for Azure)"
  type        = string
  default     = ""
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Helm release details
variable "helm_release_name" {
  description = "Name of the Helm release for Cilium"
  type        = string
  default     = "cilium"
}

variable "helm_repository" {
  description = "Repository URL for the Cilium Helm chart"
  type        = string
  default     = "https://helm.cilium.io/"
}

variable "helm_chart" {
  description = "Name of the Cilium Helm chart"
  type        = string
  default     = "cilium"
}

variable "helm_chart_version" {
  description = "Version of the Cilium Helm chart"
  type        = string
  default     = "1.17.2"
}

variable "namespace" {
  description = "Kubernetes namespace to install Cilium into"
  type        = string
  default     = "kube-system"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 1200
}

variable "helm_wait" {
  description = "Whether to wait for Helm release to complete"
  type        = bool
  default     = true
}

# Cilium configuration values

variable "gateway_api_enabled" {
  description = "Enable Gateway API support"
  type        = bool
  default     = true
}

variable "gateway_api_crd_version" {
  description = "Gateway API CRD version to install (experimental channel). Set to empty string to skip CRD installation."
  type        = string
  default     = "v1.2.1"
}

variable "kube_proxy_replacement" {
  description = "KubeProxy replacement mode (false, 'strict', 'partial', 'probe')"
  type        = string
  default     = "false"
}

variable "node_port_enabled" {
  description = "Enable NodePort service support"
  type        = bool
  default     = true
}

variable "external_ips_enabled" {
  description = "Enable ExternalIPs service support"
  type        = bool
  default     = true
}

variable "cni_exclusive" {
  description = "Make Cilium take ownership over the container runtime CNI configuration"
  type        = bool
  default     = false
}

variable "socket_lb_host_namespace_only" {
  description = "Force socket LB in host namespace only"
  type        = bool
  default     = true
}

# Prometheus configuration
variable "prometheus_enabled" {
  description = "Enable Prometheus metrics for Cilium agent"
  type        = bool
  default     = true
}

variable "prometheus_service_monitor_enabled" {
  description = "Enable Prometheus ServiceMonitor for Cilium agent"
  type        = bool
  default     = true
}

variable "operator_prometheus_enabled" {
  description = "Enable Prometheus metrics for Cilium operator"
  type        = bool
  default     = true
}

# TLS configuration
variable "tls" {
  description = "TLS configuration for Cilium"
  type        = any
  default = {
    enabled = false
  }
}

# Debug configuration
variable "debug" {
  description = "Debug configuration for Cilium"
  type        = any
  default = {
    enabled = false
  }
}

# Identity allocation mode
variable "identityAllocationMode" {
  description = "The method to use for identity allocation (CRD or kvstore)"
  type        = string
  default     = "crd"
}

# CNI configuration
variable "cni" {
  description = "CNI configuration for Cilium"
  type        = any
  default = {
    exclusive    = false
    chainingMode = null
  }
}

# Hubble configuration
variable "hubble_enabled" {
  description = "Enable Hubble"
  type        = bool
  default     = true
}

variable "hubble_listen_address" {
  description = "Hubble listen address"
  type        = string
  default     = ":4244"
}

variable "hubble_metrics_enabled" {
  description = "List of Hubble metrics to enable"
  type        = list(string)
  default = [
    "dns:labelsContext=source_namespace,destination_namespace",
    "drop:labelsContext=source_namespace,destination_namespace",
    "tcp",
    "flow",
    "port-distribution",
    "icmp",
    "httpV2:sourceContext=workload-name|pod-name|reserved-identity;destinationContext=workload-name|pod-name|reserved-identity;labelsContext=source_namespace,destination_namespace,traffic_direction"
  ]
}

variable "hubble_metrics_enable_open_metrics" {
  description = "Enable OpenMetrics format for Hubble metrics"
  type        = bool
  default     = false
}

variable "hubble_relay_enabled" {
  description = "Enable Hubble Relay"
  type        = bool
  default     = true
}

variable "hubble_ui_enabled" {
  description = "Enable Hubble UI"
  type        = bool
  default     = true
}

variable "hubble_tls_auto_enabled" {
  description = "Enable automatic TLS certificate generation for Hubble"
  type        = bool
  default     = true
}

variable "hubble_tls_auto_method" {
  description = "Method to auto-generate TLS certificates (cronJob or certmanager)"
  type        = string
  default     = "cronJob"
}

variable "hubble_tls_cert_validity_duration" {
  description = "Validity duration of the Hubble TLS certificates in days"
  type        = number
  default     = 1095
}

variable "hubble_tls_schedule" {
  description = "Cron schedule for Hubble TLS certificate generation"
  type        = string
  default     = "0 0 1 */4 *"
}

# Resource limits
variable "resources_limits_cpu" {
  description = "CPU limit for Cilium agent"
  type        = string
  default     = "1000m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Cilium agent"
  type        = string
  default     = "1Gi"
}

variable "resources_requests_cpu" {
  description = "CPU request for Cilium agent"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for Cilium agent"
  type        = string
  default     = "128Mi"
}

variable "operator_resources_limits_cpu" {
  description = "CPU limit for Cilium operator"
  type        = string
  default     = "500m"
}

variable "operator_resources_limits_memory" {
  description = "Memory limit for Cilium operator"
  type        = string
  default     = "512Mi"
}

variable "operator_resources_requests_cpu" {
  description = "CPU request for Cilium operator"
  type        = string
  default     = "50m"
}

variable "operator_resources_requests_memory" {
  description = "Memory request for Cilium operator"
  type        = string
  default     = "64Mi"
} 