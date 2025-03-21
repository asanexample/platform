terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.23.0"
    }
  }
  required_version = ">= 1.6.0"
}

provider "azurerm" {
  features {}
} 