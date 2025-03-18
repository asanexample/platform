// Base Terragrunt configuration for all modules
// This file defines the global Terragrunt configuration that applies to all modules

// Define remote state configuration using Azure Blob Storage
// Disabled for initial testing - using local state
/*
remote_state {
  backend = "azurerm"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatemulticloud${get_env("TF_VAR_environment", "dev")}"
    container_name       = "${path_relative_to_include()}"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    use_azuread_auth     = true
  }
}
*/

// Use local backend for testing
remote_state {
  backend = "local"
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  
  config = {
    path = "${path_relative_to_include()}/terraform.tfstate"
  }
}

// Generate provider configuration for each module
generate "providers" {
  path      = "providers.tf"
  if_exists = "skip"
  contents  = <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.23.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
  
  subscription_id = "${local.azure_subscription_id}"
  tenant_id       = "${local.azure_tenant_id}"
  
  use_cli = true
}

provider "aws" {
  region = "${local.aws_region}"
  
  default_tags {
    tags = {
      Environment = "${local.environment}"
      ManagedBy   = "Terragrunt"
      Project     = "Multi-Cloud Infrastructure"
    }
  }
}

provider "google" {
  project = "${local.gcp_project_id}"
  region  = "${local.gcp_region}"
}
EOF
}

// Shared inputs that apply to all modules
inputs = {
  // Common tags will be applied to all resources
  common_tags = {
    Environment = local.environment
    ManagedBy   = "Terragrunt"
    Project     = "Multi-Cloud Infrastructure"
    CostCenter  = local.cost_center
    Owner       = local.owner
  }
}

// Helper functions for standardized resource naming
locals {
  # Extract environment, region, and other global variables
  environment = get_env("TF_VAR_environment", "dev")
  
  # Default region settings for each cloud provider
  aws_region          = get_env("TF_VAR_aws_region", "us-east-1")
  azure_region        = get_env("TF_VAR_azure_region", "eastus")
  gcp_region          = get_env("TF_VAR_gcp_region", "us-east1")
  
  # Account/subscription IDs
  azure_subscription_id = get_env("TF_VAR_azure_subscription_id", "db4f1d99-0ec0-44eb-90de-41975f9bb68b")
  azure_tenant_id       = get_env("TF_VAR_azure_tenant_id", "c945e155-be68-4477-b8d7-01939adbfe55")
  gcp_project_id        = get_env("TF_VAR_gcp_project_id", "")
  
  # Organization details
  cost_center = get_env("TF_VAR_cost_center", "Engineering")
  owner       = get_env("TF_VAR_owner", "Platform Team")
  
  # Standard naming convention helpers
  # Format: {prefix}-{cloud}-{resource_type}-{env}-{region}-{name}
  # Example: ctr-az-rg-dev-eastus-networking
  
  # Common tags that will be applied to all resources
  common_tags = {
    Environment = local.environment
    ManagedBy   = "Terragrunt"
    Project     = "Multi-Cloud Infrastructure"
    CostCenter  = local.cost_center
    Owner       = local.owner
  }
} 