# Azure Terraform State Storage Module

This Terraform module creates an Azure Storage Account specifically configured for Terraform state storage following best practices for security and durability. It uses the general-purpose Storage Account module with optimized settings for reliable state management.

## Features

- **Optimized for Terraform State**: Pre-configured with best-practice settings for state management
- **Enhanced Durability**: Enforces minimum Zone-Redundant Storage (ZRS) replication
- **Data Protection**: Configures retention policies for blob and container soft-delete
- **Version History**: Enables blob versioning for state file history and recovery
- **Custom Containers**: Supports additional containers beyond the default `tfstate` container
- **Secure by Default**: Enforces secure access controls and network restrictions
- **Flexible Networking**: Optional private endpoint support for secure access

## Usage

### Basic Usage

```hcl
module "terraform_state" {
  source = "../../modules/azure/terraform_state"

  resource_group_name = "terraform-mgmt-rg"
  location            = "eastus"
  
  name_components = {
    prefix      = "tf"
    environment = "mgmt"
    region_abbv = "eus"
    instance    = "001"
  }
  
  # Optional additional containers
  additional_containers = {
    "tfplan" = {
      name                  = "tfplan"
      container_access_type = "private"
    }
  }
  
  tags = {
    Purpose     = "Terraform State"
    Environment = "Management"
  }
}
```

### With Network Restrictions

```hcl
module "terraform_state" {
  source = "../../modules/azure/terraform_state"

  resource_group_name = "terraform-mgmt-rg"
  location            = "eastus"
  
  name_components = {
    prefix      = "tf"
    environment = "mgmt"
    region_abbv = "eus"
    instance    = "001"
  }
  
  # Network security settings
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]  # Allow Azure DevOps to access state
    ip_rules       = ["203.0.113.0/24"] # Example: Allow office IP range
  }
  
  # Higher retention for Terraform state
  blob_delete_retention_days      = 30
  container_delete_retention_days = 30
  
  # Enable change feed for state auditing
  change_feed_enabled = true
}
```

### With Private Endpoint

```hcl
module "terraform_state" {
  source = "../../modules/azure/terraform_state"

  resource_group_name = "terraform-mgmt-rg"
  location            = "eastus"
  
  name_components = {
    prefix      = "tf"
    environment = "mgmt"
    region_abbv = "eus"
    instance    = "001"
  }
  
  # Private endpoint configuration
  private_endpoint = {
    create               = true
    subnet_id            = "/subscriptions/.../resourceGroups/my-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/endpoints"
    subresource_names    = ["blob"]
    private_dns_zone_ids = [
      "/subscriptions/.../resourceGroups/dns-rg/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }
  
  # Higher durability for Terraform state
  account_replication_type = "GZRS"  # Geo-Zone Redundant Storage
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| resource_group_name | Name of the resource group to deploy the storage account in | `string` | n/a | yes |
| location | Azure region where resources will be deployed | `string` | n/a | yes |
| storage_account_name | Name of the storage account (if custom naming is required) | `string` | `""` | no |
| name_components | Components to auto-generate the storage account name | `object` | See variables.tf | no |
| tfstate_container_name | Name of the container for Terraform state files | `string` | `"tfstate"` | no |
| account_replication_type | Replication type for the storage account (ZRS minimum) | `string` | `"ZRS"` | no |
| blob_delete_retention_days | Number of days to retain deleted blobs | `number` | `7` | no |
| container_delete_retention_days | Number of days to retain deleted containers | `number` | `7` | no |
| additional_containers | Additional containers to create in the storage account | `map(object)` | `{}` | no |
| network_rules | Network rules for the storage account | `object` | `{}` | no |
| private_endpoint | Configuration for private endpoint if required | `object` | `{}` | no |
| lifecycle_rules | Lifecycle rules for blob storage | `list(object)` | `[]` | no |
| change_feed_enabled | Whether the change feed is enabled | `bool` | `false` | no |
| last_access_time_enabled | Whether last access time tracking is enabled | `bool` | `false` | no |
| blob_public_access_enabled | Whether public access is allowed to containers and blobs | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| storage_account_id | ID of the created storage account |
| storage_account_name | Name of the created storage account |
| primary_access_key | Primary access key for the storage account |
| primary_connection_string | Primary connection string for the storage account |
| tfstate_container_name | Name of the Terraform state container |
| tfstate_container_id | Resource ID of the Terraform state container |
| private_endpoint_id | ID of the private endpoint if created |

## Terraform Backend Configuration

After deploying this module, you can configure your Terraform backend to use the created storage account:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-mgmt-rg"
    storage_account_name = "<storage_account_name_output>"
    container_name       = "tfstate"
    key                  = "project/environment/component.tfstate"
  }
}
```

## Notes

- This module enforces minimum zone-redundant storage (ZRS) for durability. If you specify a lower replication type like LRS, it will be upgraded to ZRS.
- Blob versioning is always enabled to maintain a history of state file changes.
- Retention policies ensure you can recover from accidental state file deletion.
- When using private endpoints, public network access is automatically disabled.
- The `key` in your backend configuration should be unique per Terraform workspace to avoid state conflicts.

## Security Considerations

- Access keys are sensitive outputs and should be handled securely.
- Consider using Terraform Cloud or Azure DevOps for remote state management to avoid the need to handle access keys directly.
- For maximum security, deploy with network restrictions or private endpoints.
- When using Azure DevOps, include "AzureServices" in the bypass list to allow pipeline access.

## License

This module is licensed under the MIT License - see the LICENSE file for details. 