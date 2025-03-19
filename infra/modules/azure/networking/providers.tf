terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.23.0"
    }
  }
  # Remove backend configuration as it's provided by Terragrunt
}

provider "azurerm" {
  features {}

  # Set the subscription ID from your Azure account
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"

  # Use CLI authentication
  # This uses the active Azure CLI session credentials
  use_cli = true
} 