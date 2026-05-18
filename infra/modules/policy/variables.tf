/**
 * # Policy Module Variables
 */

# Installation control
variable "create" {
  description = "Controls whether policy resources should be created"
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
  description = "Environment name (e.g., dev, test, prod)"
  type        = string
}

# Compliance configuration
variable "compliance_tier" {
  description = "Compliance tier to enforce (standard, hipaa, pci)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "hipaa", "pci"], var.compliance_tier)
    error_message = "compliance_tier must be one of: standard, hipaa, pci"
  }
}

# Helm chart configuration
variable "chart_version" {
  description = "Version of the Kyverno Helm chart"
  type        = string
  default     = "3.3.7"
}

variable "namespace" {
  description = "Kubernetes namespace to install Kyverno into"
  type        = string
  default     = "kyverno"
}

# Custom policies
variable "additional_policies" {
  description = "Map of policy name to YAML content for custom ClusterPolicy resources"
  type        = map(string)
  default     = {}
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
