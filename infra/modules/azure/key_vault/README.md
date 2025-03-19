# Azure Key Vault Module

This module creates an Azure Key Vault with configurable access policies, network rules, and private endpoints. It's designed to be flexible for use in various security scenarios including secret management, certificate management, and encryption key management.

## Features

- Creates a fully configured Azure Key Vault
- Supports both RBAC and access policy authorization models
- Configurable network rules to restrict access
- Optional private endpoint integration for secure network access
- Flexible naming with support for auto-generation based on naming conventions
- Support for unique naming with static suffix to avoid naming conflicts
- Comprehensive validation of input parameters
- Configurable SKU selection (standard or premium)
- Implements best practices for key vault security:
  - Purge protection enabled by default
  - Soft-delete enabled with configurable retention
  - Public network access disabled by default

## Usage

### Basic Usage with RBAC Authorization (Default)

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  name                = "my-key-vault"
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### With Unique Name Using Static Suffix

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  name                = "vipdevwuskv01"  # Using a unique static suffix (01)
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### With Access Policies (RBAC Disabled)

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  name                = "my-key-vault"
  
  enable_rbac_authorization = false
  
  access_policies = {
    "admin" = {
      object_id = "00000000-0000-0000-0000-000000000000"  # Object ID of the admin principal
      secret_permissions = [
        "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"
      ]
      key_permissions = [
        "Get", "List", "Create", "Delete", "Update"
      ]
    }
    "reader" = {
      object_id = "11111111-1111-1111-1111-111111111111"  # Object ID of the reader principal
      secret_permissions = [
        "Get", "List"
      ]
    }
  }
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### With Auto-Generated Name

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  
  # Empty name triggers auto-generation
  name = ""
  
  name_components = {
    prefix      = "vip"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### With Network Restrictions

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  name                = "my-key-vault"
  
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = ["203.0.113.0/24"]
    virtual_network_subnet_ids = ["subnet-id-1", "subnet-id-2"]
  }
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### With Private Endpoint

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  name                = "my-key-vault"
  
  private_endpoint = {
    subnet_id            = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/.../subnets/..."
    private_dns_zone_ids = ["/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"]
  }
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### AKS Integration Example

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  
  name = "vipdevwuskv01"  # Using a static unique suffix
  
  # Key Vault configuration
  sku_name                     = "standard"
  enabled_for_disk_encryption  = true
  enable_rbac_authorization    = true
  purge_protection_enabled     = true
  soft_delete_retention_days   = 90
  
  # Network settings for secure access
  network_acls = {
    bypass                     = "AzureServices"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = [
      dependency.networking.outputs.subnet_ids["az1-endpoint-subnet"]
    ]
  }
  
  # Private endpoint configuration
  private_endpoint = {
    subnet_id            = dependency.networking.outputs.subnet_ids["az1-endpoint-subnet"]
    private_dns_zone_ids = []
  }
  
  tags = {
    Component          = "KeyVault"
    CostCenter         = "Engineering"
    DataClassification = "Internal"
    Environment        = "dev"
    ManagedBy          = "Terragrunt"
    Owner              = "Platform Team"
    Project            = "Multi-Cloud Platform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group to deploy the key vault in | `string` | n/a | yes |
| location | Azure region where the key vault will be deployed | `string` | n/a | yes |
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
| private_endpoint | Configuration for the private endpoint | `object` | See below | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

### Network ACLs Object

```hcl
network_acls = {
  bypass                     = "AzureServices"  # Can be "AzureServices" or "None"
  default_action             = "Deny"           # Can be "Allow" or "Deny"
  ip_rules                   = ["203.0.113.0/24"]  # List of IP addresses or CIDR blocks
  virtual_network_subnet_ids = ["subnet-id-1"]  # List of subnet IDs
}
```

### Private Endpoint Object

```hcl
private_endpoint = {
  subnet_id            = ""     # Subnet ID for the private endpoint
  private_dns_zone_ids = []     # List of private DNS zone IDs
}
```

### Name Components Object

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

## Naming Strategies

### Static Unique Suffix

This approach uses a static unique suffix to ensure globally unique Key Vault names without changing on each apply:

```hcl
locals {
  # Use a fixed unique suffix instead of timestamp
  unique_suffix = "01"
}

inputs = {
  # Use a fixed unique name that doesn't change on every apply
  name = "vipdevwuskv${local.unique_suffix}"
}
```

### Timestamp-Based Naming (Not Recommended for Production)

An alternative approach for dev/test environments is to use a timestamp-based suffix, which ensures uniqueness but changes on each apply:

```hcl
locals {
  # Generate a unique timestamp-based suffix for the Key Vault
  timestamp_suffix = formatdate("hhmmss", timestamp())
}

inputs = {
  # Use a custom Key Vault name with timestamp
  name = "vipdeveuskv${local.timestamp_suffix}"
}
```

Note: The timestamp approach is not recommended for production as it creates a new resource on each apply.

## Testing

This module includes comprehensive Terraform tests that validate the module's functionality:

### Pre-requisites for Testing

To run the tests locally, you need:

1. Terraform 1.6.0 or higher
2. Valid Azure credentials with permissions to create resources
3. Environment variables for Azure authentication:
   ```bash
   export ARM_CLIENT_ID="your-client-id"
   export ARM_CLIENT_SECRET="your-client-secret"
   export ARM_SUBSCRIPTION_ID="your-subscription-id"
   export ARM_TENANT_ID="your-tenant-id"
   ```

### Running Tests

```bash
# Run tests for the module
cd infra/tests/modules/azure/key_vault
terraform init
terraform test
```

The tests validate:
- Basic key vault creation with default settings
- Key vault with access policies (RBAC disabled)
- Key vault with network ACLs
- Key vault with auto-generated name
- Key vault with private endpoint

## Naming Convention

This module follows the naming convention defined in the [NAMING_CONVENTIONS.md](../../../../../NAMING_CONVENTIONS.md) file. When no name is provided, it generates a name using the following pattern:

```
{prefix}{environment}{region_abbv}kv{instance}
```

Example: `vipdeveuskv001`

## Notes

1. When `enable_rbac_authorization` is set to `true` (default), any `access_policies` configurations will be ignored.
2. When a private endpoint is created (`private_endpoint.create = true`), public network access will be automatically disabled.
3. The key vault name must be globally unique across Azure and must be between 3-24 characters.
4. The default configuration follows security best practices with public network access disabled and purge protection enabled. 