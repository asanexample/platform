variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "vpc_name" {
  description = "Name of the VPC to create"
  type        = string
}

variable "address_space" {
  description = "CIDR blocks for the VPC"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnets" {
  description = "Map of subnet names to configuration"
  type = map(object({
    address_prefixes  = list(string)
    availability_zone = optional(string)
    public            = optional(bool, false)
  }))
  default = {}
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
  description = "Abbreviated region name for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_eks_networking" {
  description = "Whether to enable EKS-specific networking features (security groups, subnet tags)"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster. Used for subnet tagging when enable_eks_networking is true."
  type        = string
  default     = null
}
