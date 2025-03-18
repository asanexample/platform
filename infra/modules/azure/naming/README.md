# Azure Resource Naming Module

## Description

This module provides standardized resource naming capabilities for Azure resources based on VIP Platform conventions and Azure's naming restrictions. It ensures consistent naming across all resources and environments while adhering to Azure's resource-specific naming limitations.

## Features

- Standardized naming patterns for all Azure resources
- Automatic validation against Azure naming restrictions
- Truncation of names that exceed maximum allowed lengths
- Support for special formatting requirements (e.g., storage accounts, container registry)
- Optional customer parameter for shared/global resources
- Subnet naming with predefined types

## Usage with Terraform

```hcl
module "naming" {
  source      = "../../modules/azure/naming"
  customer    = "contoso"
  stage       = "dev"
  region_abbv = "wus"
  # prefix is optional, defaults to "vip"
}

# Then use the outputs to set resource names
resource "azurerm_resource_group" "example" {
  name     = module.naming.resource_group
  location = "West US"
}

resource "azurerm_storage_account" "example" {
  name                     = module.naming.storage_account
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Use predefined subnet types
resource "azurerm_subnet" "node_pool" {
  name                 = module.naming.subnet_node
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Use custom subnet type (by appending to base name)
resource "azurerm_subnet" "custom" {
  name                 = "${module.naming.subnet}-custom-${module.naming.region_abbv}"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}
```

## Usage with Terragrunt

```hcl
# In _envcommon/naming.hcl
terraform {
  source = "${dirname(find_in_parent_folders())}/modules/azure/naming"
}

inputs = {
  # Get variables from environment and region configuration
  customer    = local.customer_vars.locals.customer
  stage       = local.environment_vars.locals.environment
  region_abbv = local.region_vars.locals.region_code
}

# In a resource configuration file (e.g., networking.hcl)
dependency "naming" {
  config_path = "../naming"
}

inputs = {
  resource_group_name = dependency.naming.outputs.resource_group
  vnet_name           = dependency.naming.outputs.virtual_network
  subnet_names = {
    app     = dependency.naming.outputs.subnet_app
    db      = dependency.naming.outputs.subnet_db
    private = "${dependency.naming.outputs.subnet}-private-${local.region_code}"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| prefix | The prefix to use for all resources | string | "vip" | no |
| customer | The customer name to use in resource naming | string | null | no |
| stage | The environment stage (dev, preprod, prod, test, stg) | string | | yes |
| region_abbv | The abbreviated Azure region name (e.g., wus, eus, neu) | string | | yes |
| resource_type | Optional resource type for custom naming | string | null | no |
| custom_name | Optional custom name to override the generated name | string | null | no |

## Outputs

The module provides standardized names for many Azure resources, including:

- `resource_group`
- `storage_account`
- `key_vault`
- `aks_cluster`
- `virtual_network`
- `subnet` (base name)
- `subnet_node`, `subnet_app`, `subnet_api`, `subnet_db`, `subnet_endpoint`, etc.
- `front_door`
- `container_registry`
- `event_hub_namespace`
- `monitor_workspace`
- `application_insights`
- `sql_server`, `sql_database`
- `cosmos_account`
- `network_security_group`
- `bastion_host`
- `public_ip`
- ...and many more

See the outputs.tf file for the complete list of outputs.

## Naming Conventions

This module enforces the following naming pattern for most resources:
```
vip-{customer}-{stage}-{resource_type}-{region_abbv}
```

Where:
- `vip` is the default prefix (can be changed)
- `customer` is the customer name (lowercase, with special characters removed)
- `stage` is the environment (dev, preprod, prod)
- `resource_type` is a short abbreviation for the resource
- `region_abbv` is the shortened region name (e.g., wus, eus)

For shared resources that aren't customer-specific, the customer part is omitted:
```
vip-{stage}-{resource_type}-{region_abbv}
```

### Special Cases

Some Azure resources have specific naming restrictions:

**Storage Accounts**:
- 24 character limit
- No hyphens or special characters allowed
- Format: `vip{customer}{stage}sa{region_abbv}`

**Container Registry**:
- No hyphens allowed
- Format: `vip{customer}{stage}acr{region_abbv}`

## Validation

This module automatically applies the following validations:
- Name length restrictions for each resource type
- Removing characters not allowed in specific resources
- Truncating names that exceed maximum allowed lengths

## Azure Naming Rules

The module integrates Azure's naming rules and limitations, including:
- Character restrictions for each resource type
- Length limitations
- Special formatting requirements 