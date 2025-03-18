terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.23.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4.3"
    }
  }
  required_version = ">= 1.6.0"
}

provider "azurerm" {
  features {}
}

provider "random" {} 