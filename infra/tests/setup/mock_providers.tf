/**
 * # Mock Providers Module
 *
 * This module provides consistent mock values for provider configurations
 * in test files. This centralizes the mock values and makes them easy to update.
 */

variable "subscription_id" {
  description = "Mock Azure subscription ID for tests"
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "tenant_id" {
  description = "Mock Azure tenant ID for tests"
  type        = string
  default     = "11111111-1111-1111-1111-111111111111"
}

output "subscription_id" {
  description = "Mock Azure subscription ID"
  value       = var.subscription_id
}

output "tenant_id" {
  description = "Mock Azure tenant ID"
  value       = var.tenant_id
}

# Provider configuration for tests
# This can be included in test files
output "provider_block" {
  description = "Azure provider configuration block with mock values"
  value = <<-EOT
provider "azurerm" {
  features {}
  subscription_id = "${var.subscription_id}"
  tenant_id       = "${var.tenant_id}"
}
EOT
} 