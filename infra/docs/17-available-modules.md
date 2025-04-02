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

### Azure Client Config Module

**Location**: `/infra/modules/azure/client_config`

The Azure Client Config module exposes the current Azure client configuration:

- Provides access to the current Azure client configuration
- Exposes client ID, tenant ID, subscription ID, and object ID
- Useful for automatically configuring role assignments based on the current identity
- Zero resources created - purely a data source wrapper

**Example Usage**:

```hcl
module "client_config" {
  source = "../../modules/azure/client_config"
}

# Use the client configuration in role assignments
resource "azurerm_role_assignment" "example" {
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Contributor"
  principal_id         = module.client_config.object_id
}
```

### Azure Storage Roles Module

**Location**: `/infra/modules/azure/storage_roles`

The Azure Storage Roles module creates role assignments for Azure Storage accounts:

- Creates role assignments for users, groups, and service principals
- Supports multiple built-in Azure roles for storage access
- Enables granular permissions with flexible scope definitions
- Separates infrastructure provisioning from access management
- Supports container-level or account-level permissions

**Example Usage**:

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  storage_account_id = module.storage_account.id
  
  role_assignments = [
    {
      principal_id         = data.azuread_group.developers.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant write access to development team"
    },
    {
      principal_id         = data.azuread_service_principal.app.id
      role_definition_name = "Storage Blob Data Reader"
      description          = "Grant read access to app"
      scope                = "${module.storage_account.id}/blobServices/default/containers/data"
    }
  ]
}
```

### Azure Storage Container Module

**Location**: `/infra/modules/azure/storage_container`

The Azure Storage Container module creates and manages Azure Storage Containers:

- Creates containers within Azure Storage Accounts
- Configurable access levels (private, blob, container)
- Supports metadata for container description
- Enables organization of blobs into logical groups
- Name validation and optional soft delete configuration

**Example Usage**:

```hcl
module "storage_container" {
  source = "../../modules/azure/storage_container"

  storage_account_name = module.storage_account.name
  
  containers = [
    {
      name        = "data"
      access_type = "private"
    },
    {
      name        = "logs"
      access_type = "private"
      metadata = {
        description = "Container for application logs"
      }
    }
  ]
}
```

### Azure Container Registry Module

**Location**: `/infra/modules/azure/container_registry`

The Azure Container Registry module creates and configures an ACR instance:

- Support for all ACR SKUs (Basic, Standard, Premium)
- Network access controls and security configurations
- AKS integration through Azure RBAC
- Premium features including geo-replication and zone redundancy
- Encryption configuration with customer-managed keys
- Image retention policy management

**Example Usage**:

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "rg-platform-dev-eastus"
  location            = "eastus"
  environment         = "dev"
  region_abbv         = "eus"
  
  sku = "Standard"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Private DNS Zones Module

**Location**: `/infra/modules/azure/private_dns`

The Azure Private DNS Zones module creates and manages private DNS zones:

- Creates multiple private DNS zones for various Azure services
- Links zones to virtual networks for name resolution
- Enables private endpoints to be resolvable via custom DNS names
- Supports conditional creation of zones and vnet links
- Enforces naming conventions and best practices

**Example Usage**:

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = module.resource_group.name
  
  # Create zones for various Azure services
  zones = ["privatelink.azurecr.io", "privatelink.vaultcore.azure.net"]
  
  # Link zones to virtual networks for name resolution
  vnet_links = {
    "hub-vnet" = {
      vnet_id = module.networking.vnet_id
    }
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}
```

### Azure AKS Identity Module

**Location**: `/infra/modules/azure/aks_identity`

The Azure AKS Identity module creates and configures identities for AKS clusters:

- Creates user-assigned managed identities for AKS
- Assigns required RBAC roles for AKS operation
- Provides identities for Kubelet, Control Plane, and add-ons
- Supports conditional role assignments
- Separates identity management from cluster provisioning

**Example Usage**:

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name                = "id-aks-dev-eus-001"
  cluster_name        = "aks-dev-eus-001"
  node_resource_group = "rg-aks-nodes-dev-eus"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Identities Module

**Location**: `/infra/modules/azure/identities`

The Azure Identities module creates and manages user-assigned identities:

- Creates one or more user-assigned managed identities
- Assigns custom RBAC roles to the identities
- Supports federated identity credentials for workload identity
- Provides consistent naming and tagging
- Enables secure workload authentication to Azure resources

**Example Usage**:

```hcl
module "identities" {
  source = "../../modules/azure/identities"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  identities = {
    "app" = {
      name        = "id-app-dev-eus"
      description = "Identity for application workloads"
      
      role_assignments = [
        {
          scope                = module.storage_account.id
          role_definition_name = "Storage Blob Data Contributor"
        }
      ]
    }
  }
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Log Analytics Workspace Module

**Location**: `/infra/modules/azure/log_analytics`

The Azure Log Analytics Workspace module creates a centralized logging solution:

- Creates a Log Analytics Workspace for log aggregation
- Configurable retention period and SKU
- Integration with Microsoft Sentinel for security monitoring
- Daily data cap settings for cost control
- Add solutions like ContainerInsights for AKS monitoring

**Example Usage**:

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                = "log-platform-prod-eus"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  retention_in_days   = 30
  sku                 = "PerGB2018"
  
  solutions = ["ContainerInsights"]
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Managed Grafana Module

**Location**: `/infra/modules/azure/managed_grafana`

The Azure Managed Grafana module creates a fully managed Grafana instance:

- Creates an Azure Managed Grafana instance for metrics visualization
- Configures Azure Entra ID (Azure AD) integration for authentication
- Assigns administrator and viewer roles to users or groups
- Integrates with Azure Monitor and Azure Monitor Workspaces
- Configures zone redundancy for high availability

**Example Usage**:

```hcl
module "managed_grafana" {
  source = "../../modules/azure/managed_grafana"

  name                = "grf-monitoring-prod-eus"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  sku = "Standard"
  
  azure_monitor_workspace_integrations = [
    {
      workspace_id = module.monitor_workspace.id
    }
  ]
  
  admin_access = {
    users  = [data.azuread_user.admin.object_id]
    groups = [data.azuread_group.grafana_admins.object_id]
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}
```

### Azure Monitor Workspace Module

**Location**: `/infra/modules/azure/monitor_workspace`

The Azure Monitor Workspace module creates a container for metrics data:

- Creates an Azure Monitor Workspace for metrics storage
- Provides a central location for storing Prometheus metrics
- Includes query endpoint for data access
- Supports integration with Azure Managed Grafana
- Enables a managed Prometheus solution

**Example Usage**:

```hcl
module "monitor_workspace" {
  source = "../../modules/azure/monitor_workspace"

  name                = "mw-prometheus-prod-eastus"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }
}
```

### Azure Prometheus Data Collection Rule Module

**Location**: `/infra/modules/azure/prometheus_dcr`

The Azure Prometheus DCR module configures Prometheus metrics collection:

- Creates a Data Collection Rule (DCR) for Prometheus metrics collection
- Provisions a Data Collection Endpoint (DCE) for metrics ingestion
- Configures proper data flow to an Azure Monitor workspace
- Enables a managed Prometheus solution for AKS
- Sets up the infrastructure for Kubernetes monitoring

**Example Usage**:

```hcl
module "prometheus_dcr" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = module.resource_group.name
  location             = module.resource_group.location
  monitor_workspace_id = module.monitor_workspace.id
  
  name     = "dcr-prometheus-aks"
  dce_name = "dce-prometheus-aks"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }
}
```

### Azure Front Door Profile Module

**Location**: `/infra/modules/azure/frontdoor_profile`

The Azure Front Door Profile module creates the foundation for CDN services:

- Creates an Azure Front Door profile with configurable settings
- Supports both Standard and Premium SKUs
- Configurable response timeout for optimizing performance
- Serves as the parent resource for Front Door endpoints and origins
- Enables building a global content delivery network

**Example Usage**:

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                = "fd-profile-prod-global"
  resource_group_name = module.resource_group.name
  sku_name            = "Standard_AzureFrontDoor"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
  }
}
```

### Azure Front Door Endpoint Module

**Location**: `/infra/modules/azure/frontdoor_endpoint`

The Azure Front Door Endpoint module creates user-facing endpoints:

- Creates endpoints for an Azure Front Door profile
- Configures custom domain associations
- Manages TLS/SSL certificates for secure connections
- Supports WAF policy association for security
- Enables content delivery to end users

**Example Usage**:

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  name                = "fd-endpoint-prod"
  resource_group_name = module.resource_group.name
  profile_id          = module.frontdoor_profile.id
  
  host_name           = "www.example.com"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
  }
}
```

### Azure Front Door Private Link Origin Module

**Location**: `/infra/modules/azure/frontdoor_private_link`

The Azure Front Door Private Link Origin module creates secure origins:

- Creates an origin group and origin for an Azure Front Door profile
- Configures Private Link service connection for secure origin access
- Manages health probes for origin monitoring
- Provides secure connectivity to backend resources
- Enables integration with private networks

**Example Usage**:

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  resource_group_name = module.resource_group.name
  
  profile_id     = module.frontdoor_profile.id
  origin_group   = "app-backend"
  origin_name    = "app-service"
  host_name      = "app.example.com"
  private_link_id = module.app_service.id
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
  }
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

## Related Documentation

For a complete understanding of how these modules fit into the overall architecture, refer to these additional documentation resources:

### Implementation Guidance
- [Infrastructure as Code Approach](03-infrastructure-as-code.md) - Understanding the IaC methodology used in this project
- [Deployment Workflows](14-deployment-workflows.md) - Processes for deploying modules using Terragrunt
- [Testing Strategy](15-testing-strategy.md) - Approaches for validating module functionality
- [Module Design Principles](13-module-design.md) - Design patterns and principles for module development

### Architecture Context
- [Architecture Overview](02-architecture-overview.md) - High-level architecture design
- [Network Topology](07-network-topology.md) - Network design principles relevant to module implementation
- [Kubernetes Network Design](08-kubernetes-network-design.md) - Specific network considerations for AKS modules
- [Security Architecture](09-security-architecture.md) - Security principles implemented in modules

### Operational Considerations
- [Environment Management](05-environment-management.md) - Managing multiple deployment environments
- [Naming Conventions](11-naming-conventions.md) - Standardized resource naming patterns
- [Tagging Strategy](12-tagging-strategy.md) - Resource tagging guidelines
- [Troubleshooting Guide](18-troubleshooting.md) - Common issues and solutions
- [Cost Management Strategy](19-cost-management.md) - Optimizing resource costs

### Templates and Standards
- [README Standards](README-STANDARDS.md) - Standards for module documentation
- [README Templates](README-TEMPLATES/) - Templates for consistent documentation

When implementing these modules in different environments, also refer to the environment-specific documentation in the `infra/live` directory structure for configuration details tailored to each environment. 