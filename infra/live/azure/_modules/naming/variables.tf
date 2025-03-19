/**
 * Variables for the naming module
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