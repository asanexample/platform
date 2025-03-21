# Available Modules

## Overview

The VIP Platform includes a collection of reusable Terraform modules for deploying infrastructure components across different cloud providers. This document provides an overview of the available modules, their capabilities, and usage patterns.

## Azure Modules

The following modules are currently implemented for Azure:

### Azure Networking Module

**Location**: `/infra/modules/azure/networking`

The Azure Networking module creates the core networking components for an Azure environment:

- Virtual Networks with configurable address spaces
- Multiple subnets with associated Network Security Groups
- Security rules for controlling network traffic
- Support for availability zone-aware configurations
- Private DNS zones for internal service access
- Optional service endpoints for secure PaaS access

**Example Usage**:

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  name          = "vip-vnet-dev-eus-main"
  address_space = ["10.0.0.0/16"]
  
  subnets = {
    "az1-nodes" = {
      address_prefix = "10.0.0.0/24"
      security_rules = local.node_subnet_rules
    },
    "az2-nodes" = {
      address_prefix = "10.0.10.0/24"
      security_rules = local.node_subnet_rules
    },
    "endpoints" = {
      address_prefix = "10.0.30.0/24"
      security_rules = local.endpoint_subnet_rules
    }
  }
  
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Storage Account Module

**Location**: `/infra/modules/azure/storage_account`

The Azure Storage Account module creates storage accounts with proper security configurations:

- Storage accounts with configurable replication types
- Network rules for secure access
- Lifecycle management policies
- Support for blob, file, table, and queue services
- Configurable encryption settings
- Access tier optimization

**Example Usage**:

```hcl
module "storage" {
  source = "../../modules/azure/storage_account"
  
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  name                     = "vipstdeveus001"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  network_rules = {
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24"]
    virtual_network_subnet_ids = [module.networking.subnet_ids["endpoints"]]
  }
  
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Key Vault Module

**Location**: `/infra/modules/azure/key_vault`

The Azure Key Vault module creates and configures Azure Key Vault for secret management:

- Key Vault with RBAC or access policy authorization
- Network rules for secure access
- Purge protection and soft delete configurations
- Certificate, key, and secret management
- Integration with Azure AD for authentication

**Example Usage**:

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"
  
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  name            = "vip-kv-dev-eus-001"
  sku_name        = "standard"
  
  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = ["203.0.113.0/24"]
    subnet_ids     = [module.networking.subnet_ids["endpoints"]]
  }
  
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

### Azure AKS Core Module

**Location**: `/infra/modules/azure/aks_core`

The Azure AKS Core module creates the core components of an AKS cluster:

- AKS cluster with configurable Kubernetes version
- System-assigned or user-assigned identity
- Network plugin configuration
- Azure AD integration
- RBAC configuration
- Azure Policy integration
- Monitoring and logging integration

**Example Usage**:

```hcl
module "aks_core" {
  source = "../../modules/azure/aks_core"
  
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  name                = "vip-aks-dev-eus-001"
  dns_prefix          = "vip-aks-dev"
  kubernetes_version  = "1.29"
  
  default_node_pool = {
    name                = "system"
    vm_size             = "Standard_D2s_v4"
    node_count          = 3
    availability_zones  = [1, 2, 3]
    vnet_subnet_id      = module.networking.subnet_ids["nodes"]
  }
  
  identity_type          = "UserAssigned"
  user_assigned_identity_id = module.aks_identity.identity_id
  
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

### Azure AKS Node Pools Module

**Location**: `/infra/modules/azure/aks_node_pools`

The Azure AKS Node Pools module creates additional node pools for an AKS cluster:

- Multiple node pools with different VM sizes and configurations
- Availability zone awareness
- Auto-scaling configuration
- Node taints and labels
- Spot instance support
- OS disk configuration

**Example Usage**:

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"
  
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  cluster_name = module.aks_core.name
  
  node_pools = {
    "general" = {
      vm_size           = "Standard_D4s_v4"
      count             = 3
      availability_zones = [1, 2, 3]
      max_pods          = 30
      os_disk_size_gb   = 128
      vnet_subnet_id    = module.networking.subnet_ids["nodes"]
      node_labels = {
        "workload-type" = "general"
      }
    },
    "spot" = {
      vm_size          = "Standard_D2s_v4"
      count            = 0
      min_count        = 0
      max_count        = 5
      enable_auto_scaling = true
      spot_max_price   = 0.1
      vnet_subnet_id   = module.networking.subnet_ids["nodes"]
      node_labels = {
        "workload-type" = "batch"
      }
      node_taints = [
        "kubernetes.azure.com/scalesetpriority=spot:NoSchedule"
      ]
    }
  }
}
```

### Azure Resource Group Module

**Location**: `/infra/modules/azure/resource_group`

The Azure Resource Group module creates and configures resource groups:

- Resource group with appropriate naming
- Standard tags
- Resource locks for critical environments

**Example Usage**:

```hcl
module "resource_group" {
  source = "../../modules/azure/resource_group"
  
  name     = "vip-rg-dev-eus-networking"
  location = "eastus"
  
  lock_level = "CanNotDelete"  # Only for production
  
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Naming Module

**Location**: `/infra/modules/azure/naming`

The Azure Naming module provides standardized resource naming conventions:

- Consistent naming patterns for all Azure resources
- Compliance with Azure naming restrictions
- Support for multi-region and multi-environment deployments
- Configurable prefixes and suffixes

**Example Usage**:

```hcl
module "naming" {
  source = "../../modules/azure/naming"
  
  prefix      = "vip"
  environment = "dev"
  region      = "eastus"
  instance    = "001"
}

resource "azurerm_storage_account" "example" {
  name                = module.naming.storage_account_name
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  # Other storage account configuration...
}
```

## AWS Modules

AWS modules are planned for future implementation phases. This section will be updated once AWS modules are available.

## GCP Modules

GCP modules are planned for future implementation phases. This section will be updated once GCP modules are available.

## Common Modules

Common cross-cloud abstraction modules are planned for future implementation phases. This section will be updated once common modules are available.

## Module Usage Guidelines

When using these modules, follow these guidelines:

1. **Input Variables**: Review all required and optional input variables before using a module.
2. **Dependencies**: Understand module dependencies and ensure they are applied in the correct order.
3. **Outputs**: Use module outputs for referencing resources in dependent modules.
4. **Documentation**: Refer to each module's README.md file for detailed usage instructions.
5. **Testing**: Run module tests to validate functionality before implementing in production environments.

## Next Steps

To learn more about the module design principles, see [Module Design](13-module-design.md). 