# VIP Platform Naming Conventions

This document outlines the standard naming conventions used across the VIP Platform infrastructure to ensure consistency across all resources and environments.

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

## Environment Abbreviations

| Environment | Abbreviation |
|-------------|--------------|
| Development | dev          |
| Testing     | test         |
| Staging     | staging      |
| Production  | prod         |
| Operations  | ops          |

## Region Abbreviations

| Azure Region   | Abbreviation |
|----------------|--------------|
| East US        | eus          |
| West US        | wus          |
| Central US     | cus          |
| North Europe   | neu          |
| West Europe    | weu          |
| Southeast Asia | sea          |
| Australia East | aue          |
| UK South       | uks          |
| Canada Central | cac          |

## Resource Type Abbreviations

| Resource Type                              | Abbreviation | Example                                     |
|--------------------------------------------|--------------|---------------------------------------------|
| Resource Group                             | rg           | vip-rg-dev-eus-net                          |
| Virtual Network                            | vnet         | vip-vnet-dev-eus-main                       |
| Subnet                                     | subnet       | az1-node-subnet                             |
| Network Security Group                     | nsg          | az1-node-subnet-nsg                         |
| Key Vault                                  | kv           | vip-kv-dev-eus-secrets                      |
| Storage Account                            | st           | vipdeveussa001 (special format - see notes) |
| Container Registry                         | acr          | vipdevacr                                   |
| AKS Cluster                                | aks          | vip-aks-dev-eus-k8s                         |
| Public IP                                  | pip          | vip-pip-dev-eus-ingress                     |
| Load Balancer                              | lb           | vip-lb-dev-eus-app                          |
| Application Gateway                        | agw          | vip-agw-dev-eus-ingress                     |
| Private Endpoint                           | pe           | vip-pe-dev-eus-sql                          |
| Private DNS Zone                           | pdns         | privatelink.database.windows.net            |
| Front Door Profile                         | fd           | vip-fd-dev-global                           |
| Front Door Endpoint                        | fd-endpoint  | vip-fd-endpoint-dev-eus-customer            |
| Front Door Origin Group                    | fd-og        | vip-fd-og-dev-eus-customer                  |
| Front Door Origin                          | fd-origin    | vip-fd-origin-dev-eus-customer              |
| Front Door Route                           | fd-route     | vip-fd-route-dev-eus-customer               |
| Log Analytics Workspace                    | law          | vip-law-dev-eus-analytics                   |
| Monitor Workspace                          | mw           | vip-mw-dev-eus-prometheus                   |
| Data Collection Rule                       | dcr          | vip-dcr-dev-eus-prometheus                  |
| Data Collection Endpoint                   | dce          | vip-dce-dev-eus-prometheus                  |
| Managed Grafana                            | grafana      | vip-grafana-dev-eus-metrics                 |
| User-Assigned Managed Identity             | id           | vip-id-dev-eus-aks                          |
| Workload Identity                          | workid       | vip-workid-dev-eus-customer                 |
| Federated Credential                       | fedcred      | vip-fedcred-dev-eus-customer                |
| Storage Account Private Endpoint           | pe           | vip-pe-dev-eus-storage                      |
| Storage Container                          | container    | assets, logs, data                          |

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
{prefix}{env}{region_abbv}st{instance}
```

Example: `vipdeveusstdata001`

### Container Names
Container names in Storage Accounts are consistent across all deployments:
- assets
- logs
- data
- backups
- archives

### Customer-Specific Resources

For customer-specific resources:
```
{prefix}-{resource_type}-{env}-{region_abbv}-{customer}
```

Example: `vip-kv-dev-eus-customer1`

### Role Assignments

Role assignments for RBAC use a descriptive approach:
```
{resource}-{role}-{principal-type}
```

Examples:
- `storage-contributor-developers`
- `keyvault-reader-app`
- `aks-admin-operations`

### Private Link Resources

Private link resources follow:
```
{prefix}-pe-{env}-{region_abbv}-{service}
```

Example: `vip-pe-dev-eus-keyvault`

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

| Tag Name           | Description                                       | Example                            |
|--------------------|---------------------------------------------------|------------------------------------|
| Environment        | Deployment environment                            | "dev", "test", "prod"              |
| ManagedBy          | Tool managing the resource                        | "Terraform"                        |
| Component          | System component                                  | "Networking", "Compute", "Storage" |
| Project            | Project name                                      | "Multi-Cloud Platform"             |
| DataClassification | Data sensitivity                                  | "Internal", "Confidential"         |
| Region             | Azure region                                      | "eastus", "westus"                 |
| AutoShutdown       | Auto-shutdown eligibility                         | "True", "False"                    |
| CIDRHierarchy      | For network resources, position in CIDR hierarchy | "Azure-Dev-EastUS"                 |
| NetworkDesign      | Network design pattern                            | "Kubernetes3AZ"                    |
| CreatedDate        | Date when the resource was created                | "2023-06-01"                       |

## Implementation in Terraform

### Basic Naming Convention

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
  storage_account_name = "${local.prefix}${local.environment}${local.region_abbv}st001"
}
```

### Standardized Naming Module

The platform enforces standardized naming through the use of the naming module, which centralizes all resource naming logic:

```hcl
module "naming" {
  source      = "../../modules/azure/naming"
  
  prefix      = var.prefix
  environment = var.environment
  region_abbv = var.region_abbv
  customer    = var.customer  # Optional, omitted for shared resources
}

# Resource Group
module "resource_group" {
  source = "../../modules/azure/resource_group"
  
  name     = module.naming.resource_group_name
  location = var.location
  
  tags = local.tags
}

# Virtual Network
module "networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name          = module.naming.virtual_network_name
  address_space = ["10.0.0.0/16"]
  
  # ...other settings
}

# Storage Account
module "storage_account" {
  source = "../../modules/azure/storage_account"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name                     = module.naming.storage_account_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # ...other settings
}

# Key Vault
module "key_vault" {
  source = "../../modules/azure/key_vault"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name                = module.naming.key_vault_name
  
  # ...other settings
}
```

All infrastructure modules use the naming module internally. For example, the `aks_core` module automatically generates standardized resource names based on the provided prefix, customer, environment, and region abbreviation inputs.

## Reference

For CIDR allocation strategy details, see [CIDR Allocation Strategy](06-cidr-allocation.md).

For security naming considerations, see [Security Architecture](09-security-architecture.md).

For multi-cloud naming strategies, see [Multi-Cloud Strategy](04-multi-cloud-strategy.md). 