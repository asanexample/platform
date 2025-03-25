/**
 * # Provider Requirements for Azure Managed Grafana Module
 * 
 * This file defines the required providers and their versions.
 * 
 * NOTE: When using this module with Terragrunt, you need to ensure that the
 * Terragrunt configuration correctly handles the versions.tf file. If you
 * encounter versions.tf conflicts, you may need to configure Terragrunt to
 * skip generating its own versions.tf file or use alternative approaches.
 */

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.23.0"
    }
  }
  required_version = ">= 1.3.0"
} 