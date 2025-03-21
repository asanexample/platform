#!/usr/bin/env bash
# Script to update eastus terragrunt.hcl files with proper configuration

set -e

EASTUS_DIR="infra/live/azure/dev/eastus"

# Update networking module
cat > "${EASTUS_DIR}/networking/terragrunt.hcl" << EOF
# Terragrunt configuration for Azure Networking in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
  address_space = local.network_vars.locals.address_space
  subnets       = local.network_vars.locals.subnets
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the networking module
terraform {
  source = "\${get_repo_root()}/infra/modules/azure/networking"
}

# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    virtual_network = "mock-vnet"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  vnet_name           = dependency.naming.outputs.virtual_network
  address_space       = local.address_space
  subnets             = local.subnets
  tags                = local.tags
}
EOF

# Update key_vault module
cat > "${EASTUS_DIR}/key_vault/terragrunt.hcl" << EOF
# Terragrunt configuration for Azure Key Vault in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the key_vault module
terraform {
  source = "\${get_repo_root()}/infra/modules/azure/key_vault"
}

# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    key_vault = "mock-kv"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  key_vault_name      = dependency.naming.outputs.key_vault
  tags                = local.tags
}
EOF

# Update storage module
cat > "${EASTUS_DIR}/storage/terragrunt.hcl" << EOF
# Terragrunt configuration for Azure Storage in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the storage_account module
terraform {
  source = "\${get_repo_root()}/infra/modules/azure/storage_account"
}

# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    storage_account = "mockstorageacct"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name  = dependency.resource_group.outputs.name
  location             = local.region
  storage_account_name = dependency.naming.outputs.storage_account
  tags                 = local.tags
}
EOF

# Update aks_identity module
cat > "${EASTUS_DIR}/aks_identity/terragrunt.hcl" << EOF
# Terragrunt configuration for Azure AKS Identity in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the aks_identity module
terraform {
  source = "\${get_repo_root()}/infra/modules/azure/aks_identity"
}

# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_identity = "mock-identity"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  identity_name       = dependency.naming.outputs.aks_identity
  tags                = local.tags
}
EOF

# Update aks_core module
cat > "${EASTUS_DIR}/aks_core/terragrunt.hcl" << EOF
# Terragrunt configuration for Azure AKS Core in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the aks_core module
terraform {
  source = "\${get_repo_root()}/infra/modules/azure/aks_core"
}

# Set dependencies for this module
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
  }
}

dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = { "az1-kubernetes" = "mock-subnet-id" }
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "mock-identity-id"
  }
}

# Specify inputs specific to this module
inputs = {
  resource_group_name = dependency.resource_group.outputs.name
  location            = local.region
  cluster_name        = dependency.naming.outputs.aks_cluster
  kubernetes_version  = "1.27"
  identity_id         = dependency.aks_identity.outputs.id
  subnet_id           = dependency.networking.outputs.subnet_ids["az1-kubernetes"]
  tags                = local.tags
}
EOF

# Update aks_node_pools module
cat > "${EASTUS_DIR}/aks_node_pools/terragrunt.hcl" << EOF
# Terragrunt configuration for Azure AKS Node Pools in eastus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env          = local.common_vars.locals.env
  prefix       = local.common_vars.locals.prefix
  customer     = local.common_vars.locals.customer
  region       = "eastus"
  region_abbv  = "east"
  tags         = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the aks_node_pools module
terraform {
  source = "\${get_repo_root()}/infra/modules/azure/aks_node_pools"
}

# Set dependencies for this module
dependency "aks_core" {
  config_path = "../aks_core"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "mock-aks-id"
  }
}

# Specify inputs specific to this module
inputs = {
  aks_cluster_id = dependency.aks_core.outputs.id
  environment    = local.env
  region_abbv    = local.region_abbv
  node_pools = {
    "app" = {
      vm_size             = "Standard_D4s_v3"
      enable_auto_scaling = true
      min_count           = 2
      max_count           = 5
      os_disk_size_gb     = 128
      os_disk_type        = "Managed"
      max_pods            = 30
      node_labels = {
        "nodepool-type" = "app"
        "environment"   = local.env
        "region"        = local.region
      }
    }
  }
}
EOF

echo "Updated all eastus terragrunt.hcl files with proper configuration." 