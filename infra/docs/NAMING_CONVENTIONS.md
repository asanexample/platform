# Platform Naming Conventions

This document outlines the standard naming conventions used across our multi-cloud platform infrastructure to ensure consistency across all resources and environments.

## General Structure

Most resources follow this pattern:
```
{prefix}-{resource_type}-{env}-{region_abbv}-{purpose}
```

Where:
- `prefix` is our standard organization prefix (e.g., "vip")
- `resource_type` is a short abbreviation for the resource (see table below)
- `env` is the environment (dev, test, prod)
- `region_abbv` is the shortened region name (e.g., eus, wus)
- `purpose` is optional and describes the specific purpose (e.g., "main", "secondary")

## Region Abbreviations

| Azure Region | Abbreviation |
|--------------|--------------|
| East US | eus |
| West US | wus |
| Central US | cus |
| North Europe | neu |
| West Europe | weu |
| Southeast Asia | sea |
| Australia East | aue |
| UK South | uks |
| Canada Central | cac |

## Resource Type Abbreviations

| Resource Type | Abbreviation | Example |
|---------------|--------------|---------|
| Resource Group | rg | vip-rg-dev-eus-net |
| Virtual Network | vnet | vip-vnet-dev-eus-main |
| Subnet | subnet | az1-node-subnet |
| Network Security Group | nsg | az1-node-subnet-nsg |
| Key Vault | kv | vip-kv-dev-eus-secrets |
| Storage Account | sa | vipdeveussa001 (special format - see notes) |
| Container Registry | acr | vipdevacr |
| AKS Cluster | aks | vip-aks-dev-eus-k8s |
| Public IP | pip | vip-pip-dev-eus-ingress |
| Load Balancer | lb | vip-lb-dev-eus-app |
| Application Gateway | agw | vip-agw-dev-eus-ingress |
| Private Endpoint | pe | vip-pe-dev-eus-sql |
| Private DNS Zone | pdns | privatelink.database.windows.net |
| Front Door | fd | vip-fd-dev-global |
| Log Analytics Workspace | law | vip-law-dev-eus-analytics |

## Specific Resource Conventions

### Availability Zone Resources

For resources distributed across availability zones, prefix with the AZ number:
```
az{number}-{resource_type}-{purpose}
```

Examples:
- `az1-node-subnet` (Subnet for nodes in AZ1)
- `az2-lb-subnet` (Subnet for load balancers in AZ2)
- `az3-endpoint-subnet` (Subnet for private endpoints in AZ3)

### Storage Accounts
Storage accounts have a 24 character limit and cannot use hyphens. They follow this pattern:
```
{prefix}{env}{region_abbv}sa{instance}
```

Example: `vipdeveussa001`

### Deployment ID

The `deployment_id` is a special identifier used for customer applications:

- Format: Often (but not always) follows a pattern of customer name and environment
  ```
  {customer}-{env}
  ```

- Examples:
  - `mycustomer-dev`
  - `my-customer-dev`
  - `legacy-app-01` (example of pre-existing naming that doesn't follow the standard pattern)

- Usage:
  - Primarily used for Kubernetes namespace naming in workload identity federation
  - Serves as an identifier for customer-specific applications
  - Distinct from the core infrastructure naming conventions

- Important Note:
  - Pre-existing applications may have deployment IDs that don't conform to the standard pattern
  - Always verify the correct deployment_id rather than assuming the {customer}-{env} format
  - When creating new deployment IDs, prefer the standard format unless there's a specific reason to deviate

## Tagging Conventions

All resources should include the following standard tags:

| Tag Name | Description | Example |
|----------|-------------|---------|
| Environment | Deployment environment | "dev", "test", "prod" |
| ManagedBy | Tool managing the resource | "Terragrunt" |
| Component | System component | "Networking", "Compute", "Storage" |
| Project | Project name | "Multi-Cloud Platform" |
| DataClassification | Data sensitivity | "Internal", "Confidential" |
| Region | Azure region | "eastus", "westus" |
| AutoShutdown | Auto-shutdown eligibility | "True", "False" |
| CIDRHierarchy | For network resources, position in CIDR hierarchy | "Azure-Dev-EastUS" |
| NetworkDesign | Network design pattern | "Kubernetes3AZ" |

## Network Naming Hierarchy

The network naming follows the hierarchical CIDR allocation:

```
# Format for Virtual Networks
{prefix}-vnet-{env}-{region_abbv}-{purpose}

# Format for Resource Groups
{prefix}-rg-{env}-{region_abbv}-{component}
```

Examples:
- `vip-vnet-dev-eus-main` (Main VNet in East US for dev)
- `vip-rg-dev-eus-net` (Resource group for networking in East US dev)

## Implementation in Terraform

Use locals to construct resource names consistently:

```hcl
locals {
  prefix        = "vip"
  environment   = "dev"
  region        = "eastus"
  region_abbv   = "eus"
  component     = "net"
  
  # Resource Group
  resource_group_name = "${local.prefix}-rg-${local.environment}-${local.region_abbv}-${local.component}"
  
  # Virtual Network
  vnet_name = "${local.prefix}-vnet-${local.environment}-${local.region_abbv}-main"
  
  # Storage Account (no hyphens, 24 char limit)
  storage_account_name = "${local.prefix}${local.environment}${local.region_abbv}sa001"
}
```

## Standardized Naming Implementation

The platform now enforces standardized naming through the use of the naming module, which centralizes all resource naming logic:

```hcl
module "naming" {
  source      = "../../modules/azure/naming"
  
  prefix      = "vip"
  customer    = "contoso"  # Optional, omitted for shared resources
  stage       = "dev"
  region_abbv = "eus"
}

# Use naming module outputs for resource names
resource "azurerm_resource_group" "example" {
  name     = module.naming.resource_group
  location = "East US"
}

resource "azurerm_virtual_network" "example" {
  name                = module.naming.virtual_network
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_storage_account" "example" {
  name                     = module.naming.storage_account
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
```

All infrastructure modules use the naming module internally. For example, the hosting module automatically generates standardized resource names based on the provided prefix, customer, stage, and region abbreviation inputs.

## Reference

For CIDR allocation strategy details, see [CIDR Allocation Strategy](cidr-allocation.md). 