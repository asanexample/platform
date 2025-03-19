# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env           = local.common_vars.locals.env
  prefix        = local.common_vars.locals.prefix
  customer      = local.common_vars.locals.customer
  region        = "eastus"
  region_abbv   = "eus"
  tags          = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration, which has settings common to all environments
include "root" {
  path = find_in_parent_folders()
}

# Configure terraform to use appropriate backend
terraform {
  source = "${get_repo_root()}/infra/modules/azure/hosting"
}

# Specify inputs specific to this environment
inputs = {
  # Naming/tagging
  prefix      = local.prefix
  customer    = local.customer
  stage       = local.env
  region_abbv = local.region_abbv
  
  # Resource group
  location = local.region
  
  # VNet configuration
  address_space = ["10.10.0.0/16"]  # East US QaaS
  
  # Subnets
  subnets = {
    # AZ1 subnets
    "az1-node-subnet" = {
      address_prefixes = ["10.10.0.0/20"]
    }
    "az1-pod-subnet" = {
      address_prefixes = ["10.10.16.0/20"]
    }
    "az1-endpoint-subnet" = {
      address_prefixes = ["10.10.32.0/24"]
    }
    
    # AZ2 subnets
    "az2-node-subnet" = {
      address_prefixes = ["10.10.64.0/20"]
    }
    "az2-pod-subnet" = {
      address_prefixes = ["10.10.80.0/20"]
    }
    "az2-endpoint-subnet" = {
      address_prefixes = ["10.10.96.0/24"]
    }
    
    # AZ3 subnets
    "az3-node-subnet" = {
      address_prefixes = ["10.10.128.0/20"]
    }
    "az3-pod-subnet" = {
      address_prefixes = ["10.10.144.0/20"]
    }
    "az3-endpoint-subnet" = {
      address_prefixes = ["10.10.160.0/24"]
    }
    
    # Shared subnets
    "gateway-subnet" = {
      address_prefixes = ["10.10.192.0/24"]
    }
    "bastion-subnet" = {
      address_prefixes = ["10.10.193.0/24"]
    }
  }
  
  # Storage account configuration
  storage_account_tier       = "Standard"
  storage_replication_type   = "LRS"
  storage_allowed_subnets    = []
  storage_allow_public       = true
  
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
  
  # AKS node pools
  aks_default_nodepool_vm_size = "Standard_D4s_v3"
  aks_default_nodepool_count   = 3
  
  # AKS subnet mapping
  aks_az_subnet_names = {
    "1" = "az1-node-subnet"
    "2" = "az2-node-subnet"
    "3" = "az3-node-subnet"
  }
  
  # Tags
  tags = merge(local.tags, {
    Environment = local.env
    Region      = local.region
    Component   = "Hosting"
  })
} 