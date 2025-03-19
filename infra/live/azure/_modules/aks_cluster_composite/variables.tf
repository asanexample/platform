/**
 * Variables for the AKS cluster composite module
 */

variable "customer" {
  description = "Customer name to use in resource naming (optional for shared resources)"
  type        = string
  default     = null
}

variable "prefix" {
  description = "Prefix to use for resource naming (usually 'vip')"
  type        = string
  default     = "vip"
}

variable "stage" {
  description = "Environment stage (dev, test, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "region_abbv" {
  description = "Abbreviated Azure region name (e.g., eus, wus, etc.)"
  type        = string
  default     = "eus"
}

variable "create_resources" {
  description = "Whether to create AKS cluster resources"
  type        = bool
  default     = true
}

variable "location" {
  description = "Azure region where resources will be deployed"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group for AKS resources"
  type        = string
  default     = null
} 