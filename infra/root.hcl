// Base Terragrunt configuration for all modules
// This file defines the global Terragrunt configuration that applies to all modules

// Use OpenTofu instead of Terraform
terraform_binary = "tofu"

// Cloud-aware remote state routing.
// AWS modules → S3 + DynamoDB locking (bucket created by state-bootstrap module).
// Azure/GCP modules → Azure Blob Storage (shared ops subscription).
// The state-bootstrap module overrides this with a local backend.
remote_state {
  backend = local._cloud == "aws" ? "s3" : "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = local._cloud == "aws" ? {
    bucket         = "tfstate-mgmt-851725353202"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    } : {
    subscription_id      = "9dc5edc4-8c4e-41a1-a4f8-2183c4e91954"
    tenant_id            = "c945e155-be68-4477-b8d7-01939adbfe55"
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatemulticloud"
    container_name       = "terraformstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    use_azuread_auth     = true
  }
}

// Cloud-aware provider generation.
// Each cloud gets only its own provider — avoids cross-cloud auth failures.
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    local._cloud == "aws" ? <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.91.0"
    }
  }
}
EOF
    : local._cloud == "gcp" ? <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.26.0"
    }
  }
}
EOF
    : <<EOF
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.25.0"
    }
  }
}
EOF
  )
}

generate "provider_azure" {
  path      = "provider_azure.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    local._cloud == "azure" ? <<EOF
provider "azurerm" {
  features {}
  subscription_id = "${local.azure_subscription_id}"
  tenant_id       = "${local.azure_tenant_id}"
}
EOF
    : ""
  )
}

generate "provider_aws" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    local._cloud == "aws" ? <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
    : ""
  )
}

generate "provider_gcp" {
  path      = "provider_gcp.tf"
  if_exists = "overwrite_terragrunt"
  contents = (
    local._cloud == "gcp" ? <<EOF
provider "google" {
  project = "${local.gcp_project_id}"
  region  = "${local.gcp_region}"
}
EOF
    : ""
  )
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
  # Detect cloud provider from directory path (live/aws/... vs live/azure/...)
  _path_parts_cloud = split("/", path_relative_to_include())
  _cloud            = try(local._path_parts_cloud[1], "azure")

  # Extract environment, region, and other global variables
  environment = get_env("TF_VAR_environment", "dev")

  # Get environment-specific variables from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl", "${get_terragrunt_dir()}/dummy.hcl"))

  # Default region settings for each cloud provider
  aws_region   = get_env("TF_VAR_aws_region", "us-east-1")
  azure_region = get_env("TF_VAR_azure_region", "eastus")
  gcp_region   = get_env("TF_VAR_gcp_region", "us-east1")

  # Account/subscription IDs - both subscription_id and tenant_id must be in env.hcl
  azure_subscription_id = try(local.environment_vars.locals.subscription_id, "")
  azure_tenant_id       = try(local.environment_vars.locals.tenant_id, "")
  gcp_project_id        = try(local.environment_vars.locals.gcp_project_id, "")

  # Organization details
  cost_center = get_env("TF_VAR_cost_center", "Engineering")
  owner       = get_env("TF_VAR_owner", "Platform Team")

  # Standard naming convention helpers
  # Format: {resource_type}-{workload}-{env}-{region}-{name}
  # Example: rg-platform-dev-eus-networking

  # Common tags that will be applied to all resources
  common_tags = {
    Environment = local.environment
    ManagedBy   = "Terragrunt"
    Project     = "Multi-Cloud Infrastructure"
    CostCenter  = local.cost_center
    Owner       = local.owner
  }
} 