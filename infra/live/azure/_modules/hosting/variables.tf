/**
 * Variables for the hosting composite module
 */

variable "customer" {
  description = "Customer name to use in resource naming (optional for shared resources)"
  type        = string
  default     = null
} 