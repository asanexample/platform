variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network to create"
  type        = string
}

variable "vpc_name" {
  description = "Alias for network_name (cross-cloud interface compatibility)"
  type        = string
  default     = null
}

variable "address_space" {
  description = "Logical address space for the VPC (GCP VPCs are global; CIDRs live on subnets). Kept for cross-cloud interface parity."
  type        = list(string)
  default     = ["10.0.0.0/16"]

  validation {
    condition     = length(var.address_space) > 0
    error_message = "At least one address space CIDR must be provided."
  }
}

variable "subnets" {
  description = "Map of subnet names to configuration"
  type = map(object({
    address_prefixes = list(string)
    region           = string
    secondary_ranges = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for name, subnet in var.subnets : length(subnet.address_prefixes) > 0
    ])
    error_message = "Each subnet must have at least one address prefix."
  }
}

variable "environment" {
  description = "Environment name (e.g. ops, dev, staging, prod)"
  type        = string
}

variable "workload" {
  description = "Workload identifier for resource names"
  type        = string
}

variable "region_abbv" {
  description = "Short region abbreviation used in resource naming"
  type        = string
}

variable "labels" {
  description = "Labels to apply to all resources (GCP equivalent of tags)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Alias for labels (cross-cloud interface compatibility). Merged with labels; labels take precedence."
  type        = map(string)
  default     = {}
}

# GKE Networking Configuration Parameters
variable "enable_gke_networking" {
  description = "Whether to enable GKE-specific networking features"
  type        = bool
  default     = false
}

variable "gke_cluster_name" {
  description = "Name of the GKE cluster. Used for naming related networking resources."
  type        = string
  default     = null
}

variable "gke_pod_cidr" {
  description = "Secondary IP range CIDR for GKE pods"
  type        = string
  default     = null
}

variable "gke_service_cidr" {
  description = "Secondary IP range CIDR for GKE services"
  type        = string
  default     = null
}

variable "enable_cloud_nat" {
  description = "Whether to create a Cloud Router and Cloud NAT for outbound internet access"
  type        = bool
  default     = true
}

variable "cloud_nat_region" {
  description = "Region for the Cloud Router and Cloud NAT. Defaults to the first subnet's region."
  type        = string
  default     = null
}
