/**
 * # Provider Requirements for Azure Managed Grafana Module
 * 
 * This file defines the required providers and their versions.
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