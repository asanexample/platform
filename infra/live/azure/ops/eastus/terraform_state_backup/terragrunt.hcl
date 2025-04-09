# Terragrunt configuration for Terraform State Backup module in operations environment

# Load common variables
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags,
    {
      component  = "terraform-state-backup"
      managed-by = "terragrunt"
    }
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Set dependency on resource group
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name     = "mock-rg"
    location = "eastus"
  }
}

# Set dependency on log analytics workspace for monitoring
dependency "log_analytics" {
  config_path = "../log_analytics"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-la"
    name = "mock-la"
  }
}

# Set dependency on storage (where the Terraform state is stored)
dependency "storage" {
  config_path = "../storage"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mockstorageaccount"
    name = "mockstorageaccount"
  }
}

# Set dependency on application insights for monitoring
dependency "application_insights" {
  config_path = "../application_insights"
  skip_outputs = true
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id                       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Insights/components/mock-appinsights"
    name                     = "mock-appinsights"
    connection_string        = "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://eastus-0.in.applicationinsights.azure.com/;LiveEndpoint=https://eastus.livediagnostics.monitor.azure.com/"
    instrumentation_key      = "00000000-0000-0000-0000-000000000000"
  }
}

# Set terraform source
terraform {
  source = "${get_path_to_repo_root()}/infra/modules/azure/terraform_state_backup"
}

# Configure inputs
inputs = {
  # Resource information
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  backup_location     = "westus" # Use a different region for disaster recovery
  
  # Environment information
  environment = local.env
  region_abbv = local.region_abbv
  
  # Source storage account information (where Terraform state is stored)
  source_storage_account_name = dependency.storage.outputs.name
  source_storage_account_id   = dependency.storage.outputs.id
  source_container_name       = "terraform-state"
  
  # Backup storage account information
  backup_storage_account_name = "tfstatebackup${local.env}${local.region_abbv}"
  
  # Monitoring configuration
  log_analytics_workspace_id = dependency.log_analytics.outputs.id
  application_insights_connection_string = dependency.application_insights.outputs.connection_string
  application_insights_key = dependency.application_insights.outputs.instrumentation_key
  
  # Alert configuration
  alert_email = "platform-team@example.com" # Replace with your team's email address
  
  # Backup configuration
  backup_frequency = "daily"
  daily_backup_time = 2 # 2 AM
  backup_retention_days = 90
  
  # Network access configuration
  allowed_ip_ranges = [] # Empty list restricts access to virtual networks and service endpoints only
  allowed_subnet_ids = []
  
  # Tags
  tags = local.tags
} 