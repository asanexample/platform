/**
 * Provider requirements for the AKS Core module
 */

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.23.0, < 5.0.0"
    }
  }
  
  required_version = ">= 1.3.0"
} 