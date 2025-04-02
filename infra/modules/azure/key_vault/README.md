# Azure Key Vault Module

## Overview

This module creates an Azure Key Vault with configurable access policies, network rules, and private endpoints. It provides a secure solution for storing and managing secrets, certificates, and keys with support for both RBAC and Access Policy authorization models.

## Features

- Creates a fully configured Azure Key Vault with flexible naming options
- Supports both RBAC and access policy authorization models
- Configures network rules to restrict access based on IP ranges and VNet integration
- Implements private endpoint integration for secure network access
- Enforces security best practices including purge protection and soft-delete
- Provides flexible naming with support for auto-generation based on conventions
- Supports unique naming with static suffix to avoid naming conflicts
- Implements comprehensive validation of input parameters
- Offers configurable SKU selection (standard or premium)
- Enables disk encryption integration (optional)

## Usage

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = "kv-platform-prod-01"
  
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "Platform"
  }
}
```

## Examples

### Basic Key Vault with RBAC Authorization

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = "kv-platform-dev-01"
  
  # Default configuration uses RBAC authorization
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Key Vault with Access Policies

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = "kv-platform-dev-02"
  
  enable_rbac_authorization = false
  
  access_policies = {
    "admin" = {
      object_id = data.azuread_group.security_admins.object_id
      secret_permissions = [
        "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
      ]
      key_permissions = [
        "Get", "List", "Create", "Delete", "Update"
      ]
      certificate_permissions = [
        "Get", "List", "Create", "Delete", "Update", "Import"
      ]
    },
    "app" = {
      object_id = data.azuread_service_principal.app.object_id
      secret_permissions = [
        "Get", "List"
      ]
    }
  }
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Key Vault with Network Restrictions and Private Endpoint

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  name                = "kv-platform-prod-03"
  
  # Network access controls
  public_network_access_enabled = false
  
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["203.0.113.0/24"]
    virtual_network_subnet_ids = [module.networking.subnet_ids["endpoints"]]
  }
  
  # Private endpoint configuration
  private_endpoint = {
    subnet_id            = module.networking.subnet_ids["endpoints"]
    private_dns_zone_ids = [module.private_dns.zones["privatelink.vaultcore.azure.net"].id]
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Security    = "High"
  }
}
```

### AKS Integration with Auto-Generated Name

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  # Auto-generate name based on components
  name = ""
  name_components = {
    prefix      = "vip"
    environment = "prod"
    region_abbv = "eus"
    instance    = "001"
  }
  
  # Key Vault configuration
  sku_name                   = "standard"
  enabled_for_disk_encryption = true
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  
  # Network settings for secure access
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = [module.networking.subnet_ids["aks-endpoints"]]
  }
  
  # Private endpoint configuration
  private_endpoint = {
    subnet_id            = module.networking.subnet_ids["aks-endpoints"]
    private_dns_zone_ids = [module.private_dns.zones["privatelink.vaultcore.azure.net"].id]
  }
  
  tags = {
    Component          = "KeyVault"
    Environment        = "Production"
    ManagedBy          = "Terraform"
    Project            = "AKS Platform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| resource_group_name | Name of the resource group to deploy the key vault in | `string` |
| location | Azure region where the key vault will be deployed | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the key vault (if custom naming is required) | `string` | `""` | no |
| name_components | Components to auto-generate the key vault name if 'name' is not provided | `object` | `{}` | no |
| sku_name | SKU name for the key vault (standard or premium) | `string` | `"standard"` | no |
| enable_rbac_authorization | Whether to enable RBAC authorization for the key vault | `bool` | `true` | no |
| enabled_for_disk_encryption | Whether the key vault is enabled for disk encryption | `bool` | `false` | no |
| purge_protection_enabled | Whether purge protection is enabled for the key vault | `bool` | `true` | no |
| soft_delete_retention_days | Number of days for soft delete retention (7-90 days) | `number` | `90` | no |
| public_network_access_enabled | Whether public network access is enabled for the key vault | `bool` | `false` | no |
| network_acls | Network ACLs for the key vault | `object` | `null` | no |
| access_policies | Map of access policies for the key vault (used only when RBAC authorization is disabled) | `map(object)` | `{}` | no |
| private_endpoint | Configuration for the private endpoint | `object` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

### Nested Object Structures

#### Network ACLs Object

```hcl
network_acls = {
  bypass                     = "AzureServices"  # Can be "AzureServices" or "None"
  default_action             = "Deny"           # Can be "Allow" or "Deny"
  ip_rules                   = ["203.0.113.0/24"]  # List of IP addresses or CIDR blocks
  virtual_network_subnet_ids = ["subnet-id-1"]  # List of subnet IDs
}
```

#### Private Endpoint Object

```hcl
private_endpoint = {
  subnet_id            = ""     # Subnet ID for the private endpoint
  private_dns_zone_ids = []     # List of private DNS zone IDs
}
```

#### Name Components Object

```hcl
name_components = {
  prefix      = "vip"      # Organization prefix
  environment = "dev"      # Environment name
  region_abbv = "eus"      # Region abbreviation
  instance    = "001"      # Instance number
}
```

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the created Key Vault |
| name | Name of the created Key Vault |
| uri | URI of the created Key Vault |
| tenant_id | Tenant ID of the Key Vault |
| public_network_access_enabled | Whether public network access is enabled for the Key Vault |
| access_policy_ids | IDs of the created access policies |
| private_endpoint_ids | IDs of the created private endpoints |

## Module Resources

This module creates the following resources:
- Azure Key Vault
- Key Vault Access Policies (when RBAC is disabled)
- Private Endpoint (optional)
- Private DNS Zone Group (optional, for private endpoint)

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation
- [networking](../networking) - For network integration, including subnet references for private endpoints
- [private_dns](../private_dns) - For private endpoint DNS zone integration

## Authentication and Authorization Models

### RBAC Authorization (Recommended)

Role-based access control (RBAC) is the recommended authorization model:

- Set `enable_rbac_authorization = true` (default)
- Use standard Azure RBAC roles for key vault management:
  - Key Vault Administrator
  - Key Vault Certificates Officer
  - Key Vault Crypto Officer
  - Key Vault Crypto Service Encryption User
  - Key Vault Crypto User
  - Key Vault Reader
  - Key Vault Secrets Officer
  - Key Vault Secrets User

### Access Policy Authorization

Traditional access policies can be used for backward compatibility:

- Set `enable_rbac_authorization = false`
- Define access policies using the `access_policies` variable
- Specify permissions for secrets, keys, and certificates per principal

**Note:** When `enable_rbac_authorization` is set to `true`, any `access_policies` configurations will be ignored.

## Naming Strategies

### Static Unique Suffix

This approach uses a static unique suffix to ensure globally unique Key Vault names without changing on each apply:

```hcl
locals {
  # Use a fixed unique suffix instead of timestamp
  unique_suffix = "01"
}

module "key_vault" {
  # Use a fixed unique name that doesn't change on every apply
  name = "kv-platform-prod-${local.unique_suffix}"
  # ...
}
```

### Auto-Generated Naming

When no name is provided, the module generates a name using the following pattern:

```
{prefix}{environment}{region_abbv}kv{instance}
```

Example: `vipdeveuskv001`

## Security Best Practices

This module implements several security best practices:

1. **Purge Protection** - Enabled by default to prevent accidental or malicious deletion
2. **Soft-Delete** - Enabled with configurable retention period (default: 90 days)
3. **Network Isolation** - Public network access disabled by default
4. **Private Endpoints** - Support for private connectivity from virtual networks
5. **RBAC Authorization** - Enabled by default for granular access control
6. **SKU Selection** - Standard SKU by default, with option for Premium for HSM-backed keys

## Notes

1. Key vault names must be globally unique across Azure and must be between 3-24 characters.
2. When a private endpoint is created, public network access will be automatically disabled.
3. For production use, consider implementing the following:
   - Use Premium SKU for HSM-backed keys for critical secrets
   - Enable private endpoints and disable public network access
   - Configure diagnostic settings for audit logging
   - Implement key rotation policies for secrets and keys
4. The default configuration follows security best practices with public network access disabled and purge protection enabled.

## Testing

This module includes Terraform tests that validate the module's functionality:

### Prerequisites for Testing

To run the tests locally, you need:

1. Terraform 1.6.0 or higher
2. Valid Azure credentials with permissions to create resources
3. Environment variables for Azure authentication

### Running Tests

```bash
# Run tests for the module
cd infra/tests/modules/azure/key_vault
terraform init
terraform test
```

## License

This module is licensed under the MIT License. 