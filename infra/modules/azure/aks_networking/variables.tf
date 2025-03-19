/**
 * # AKS Networking Module - Variables
 *
 * This module configures networking for AKS clusters, including private DNS zones,
 * network policies, and connection settings.
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
  default     = null
  validation {
    condition     = var.customer == null ? true : length(var.customer) <= 15
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
  description = "The resource group name where the networking resources will be created"
  type        = string
  validation {
    condition     = length(var.resource_group_name) >= 1 && length(var.resource_group_name) <= 90
    error_message = "The resource group name must be between 1 and 90 characters."
  }
}

variable "location" {
  description = "The Azure location where the networking resources will be deployed"
  type        = string
}

# ---------------------------------------------------------------------------------------------------------------------
# NETWORK CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------

variable "cluster_name" {
  description = "The name of the AKS cluster"
  type        = string
}

variable "node_resource_group" {
  description = "The name of the node resource group created by AKS"
  type        = string
}

variable "network_plugin" {
  description = "The network plugin to use for the AKS cluster"
  type        = string
  default     = "azure"
  validation {
    condition     = contains(["azure", "kubenet", "none"], var.network_plugin)
    error_message = "The network plugin must be one of: azure, kubenet, none."
  }
}

variable "network_plugin_mode" {
  description = "The network plugin mode to use for the AKS cluster. Valid for Azure CNI only."
  type        = string
  default     = "overlay"
  validation {
    condition     = contains(["overlay", ""], var.network_plugin_mode)
    error_message = "The network plugin mode must be either 'overlay' or empty string."
  }
}

variable "network_policy" {
  description = "The network policy to use for the AKS cluster"
  type        = string
  default     = "none"
  validation {
    condition     = contains(["azure", "calico", "none"], var.network_policy)
    error_message = "The network policy must be one of: azure, calico."
  }
}

variable "network_data_plane" {
  description = "The network data plane to use for the AKS cluster"
  type        = string
  default     = "none"
  validation {
    condition     = contains(["azure", "cilium", "none"], var.network_data_plane)
    error_message = "The network data plane must be one of: azure, cilium."
  }
}

variable "pod_cidr" {
  description = "The CIDR for pod IPs when using kubenet"
  type        = string
  default     = null
}

variable "service_cidr" {
  description = "The CIDR for Kubernetes services"
  type        = string
  default     = "10.0.0.0/16"
}

variable "dns_service_ip" {
  description = "The IP address for the DNS service"
  type        = string
  default     = "10.0.0.10"
}

variable "docker_bridge_cidr" {
  description = "The CIDR for the Docker bridge network"
  type        = string
  default     = "172.17.0.1/16"
}

variable "subnet_id" {
  description = "The ID of the subnet where the AKS cluster will be deployed"
  type        = string
  default     = null
}

variable "private_cluster_enabled" {
  description = "Whether the AKS cluster is a private cluster"
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "The ID of the Private DNS Zone for private cluster"
  type        = string
  default     = null
}

variable "private_cluster_public_fqdn_enabled" {
  description = "Whether to enable public FQDN for private clusters"
  type        = bool
  default     = false
}

variable "vnet_integration_enabled" {
  description = "Whether to enable VNet integration for the cluster control plane"
  type        = bool
  default     = false
}

variable "authorized_ip_ranges" {
  description = "The IP ranges authorized for API server access"
  type        = list(string)
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