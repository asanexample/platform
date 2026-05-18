# Azure Key Vault Module

Creates a Key Vault with access policies, network rules, and optional private endpoint for secure secret, key, and certificate storage.

## Usage

```hcl
module "key_vault" {
  source = "../key_vault"

  create = true

  resource_group_name        = "rg-platform-prod-eus"
  location                   = "eastus"
  name                       = "kv-platform-prod-eus-001"
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoint = {
    create               = true
    subnet_id            = module.networking.subnet_ids["endpoints"]
    private_dns_zone_ids = [module.private_dns.private_dns_zone_ids["keyvault"]]
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "key_vault" {
  source = "../key_vault"
  create = false
}
```

### Auto-generated name

```hcl
module "key_vault" {
  source = "../key_vault"

  create = true

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"

  name_components = {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_access_policy.policies](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_private_endpoint.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | Azure region where the key vault will be deployed | `string` | n/a | yes |
| resource_group_name | Name of the resource group to deploy the key vault in | `string` | n/a | yes |
| access_policies | Map of access policies for the key vault (used only when RBAC authorization is disabled) | <pre>map(object({<br/>    tenant_id               = optional(string)<br/>    object_id               = string<br/>    key_permissions         = optional(list(string), [])<br/>    secret_permissions      = optional(list(string), [])<br/>    certificate_permissions = optional(list(string), [])<br/>    storage_permissions     = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| enable_rbac_authorization | Whether to enable RBAC authorization for the key vault | `bool` | `true` | no |
| enabled_for_disk_encryption | Whether the key vault is enabled for disk encryption | `bool` | `false` | no |
| name | Name of the key vault (if custom naming is required). If not provided, it will be auto-generated based on naming components. | `string` | `null` | no |
| name_components | Components to auto-generate the key vault name if 'name' is not provided | <pre>object({<br/>    workload    = optional(string, "platform")<br/>    environment = optional(string, "dev")<br/>    region_abbv = optional(string, "eus")<br/>    instance    = optional(string, "001")<br/>  })</pre> | `{}` | no |
| network_acls | Network ACLs for the key vault | <pre>object({<br/>    bypass                     = optional(string, "AzureServices")<br/>    default_action             = optional(string, "Deny")<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `null` | no |
| private_endpoint | Configuration for private endpoint if required | <pre>object({<br/>    create               = optional(bool, false)<br/>    name                 = optional(string, "")<br/>    subnet_id            = optional(string, "")<br/>    private_dns_zone_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| public_network_access_enabled | Whether public network access is enabled for the key vault | `bool` | `false` | no |
| purge_protection_enabled | Whether purge protection is enabled for the key vault | `bool` | `true` | no |
| sku_name | SKU name for the key vault (standard or premium) | `string` | `"standard"` | no |
| soft_delete_retention_days | Number of days for soft delete retention (7-90 days) | `number` | `90` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| access_policy_ids | IDs of the created access policies |
| create | Whether resources were created |
| id | ID of the created Key Vault |
| name | Name of the created Key Vault |
| private_endpoint_ids | IDs of the created private endpoints |
| public_network_access_enabled | Whether public network access is enabled for the Key Vault |
| tenant_id | Tenant ID of the Key Vault |
| uri | URI of the created Key Vault |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) — Provides standardized resource names
- [resource_group](../resource_group) — Provides the resource group to deploy into

## Notes

- Name is auto-generated from `name_components` if `name` is null. Names must be globally unique, 3-24 characters, alphanumeric and hyphens only.
- Supports both RBAC (default, recommended) and access policy authorization models. When RBAC is enabled, `access_policies` are ignored.
