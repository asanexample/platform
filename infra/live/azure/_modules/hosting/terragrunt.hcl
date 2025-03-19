# Terragrunt configuration for the hosting composite module

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependencies
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
    virtual_network = "mock-vnet"
    storage_account = "mocksa"
    key_vault = "mock-kv"
    aks_cluster = "mock-aks"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
    subnet_ids = {
      "az1-node-subnet" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-node-subnet"
      "az2-node-subnet" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az2-node-subnet"
      "az3-node-subnet" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az3-node-subnet"
    }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "storage_account" {
  config_path = "../storage_account"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mocksa"
    name = "mocksa"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "key_vault" {
  config_path = "../key_vault"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.KeyVault/vaults/mock-kv"
    name = "mock-kv"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "aks_cluster" {
  config_path = "../aks_cluster_composite"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
    name = "mock-aks"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Configure the module source - We'll use the hosting module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/hosting"
}

# Common inputs for the hosting module
inputs = {
  # Naming/tagging
  prefix      = "vip"
  customer    = null
  stage       = "dev"
  region_abbv = "eus"
  
  # Resource group
  location = "eastus"
  
  # VNet configuration - use region-specific values
  address_space = ["10.0.0.0/16"]
  
  # Default empty subnets - region-specific configs should override
  subnets = {}
  
  # Storage account configuration
  storage_account_tier       = "Standard"
  storage_replication_type   = "LRS"
  storage_allowed_subnets    = []
  storage_allow_public       = false
  
  # AKS configuration
  create_aks_cluster            = true
  aks_kubernetes_version        = "1.28.3"
  aks_sku_tier                  = "Standard"
  aks_network_plugin            = "azure"
  aks_network_policy            = "calico"
  aks_service_cidr              = "10.0.0.0/16"
  aks_dns_service_ip            = "10.0.0.10"
  aks_availability_zones        = ["1", "2", "3"]
  aks_workload_identity_enabled = true
  aks_oidc_issuer_enabled       = true
  
  # Default node pool
  aks_default_nodepool_vm_size = "Standard_D4s_v3"
  aks_default_nodepool_count   = 3
  
  # AKS subnet mapping - region-specific configs should override
  aks_az_subnet_names = {}
  
  # Tags
  tags = {
    Environment        = "dev"
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
  }
} 