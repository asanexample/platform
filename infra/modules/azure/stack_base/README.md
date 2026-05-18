# Azure Base Infrastructure Stack

Composite module that wires together `resource_group`, `networking`, and `key_vault` into a single deployable unit.

## Usage

```hcl
module "base" {
  source = "../stack_base"

  create      = true
  name        = "platform-dev-eus"
  location    = "eastus"
  environment = "dev"
  workload    = "platform"
  region_abbv = "eus"

  address_space = ["10.104.0.0/16"]
  subnets = {
    "az1-kubernetes" = {
      address_prefixes  = ["10.104.0.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
  }

  enable_aks_networking = true
  aks_subnet_name      = "az1-kubernetes"
  aks_cluster_name     = "aks-platform-dev-eus"

  enable_key_vault = true
  key_vault_sku    = "standard"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "base" {
  source = "../stack_base"

  create        = false
  name          = "placeholder"
  location      = "eastus"
  environment   = "dev"
  workload      = "platform"
  region_abbv   = "eus"
  address_space = ["10.0.0.0/16"]
}
```

### Networking only (no Key Vault)

```hcl
module "base" {
  source = "../stack_base"

  create      = true
  name        = "platform-ops-wus"
  location    = "westus"
  environment = "ops"
  workload    = "platform"
  region_abbv = "wus"

  address_space = ["10.200.0.0/16"]
  subnets = {
    "az1-kubernetes" = {
      address_prefixes = ["10.200.0.0/24"]
    }
  }

  enable_key_vault = false
}
```

<!-- BEGIN_TF_DOCS -->


## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| address_space | VNet address space CIDR blocks | `list(string)` | n/a | yes |
| environment | Environment name (dev, staging, prod, ops) | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| name | Base name used to derive resource names (resource group, VNet, key vault) | `string` | n/a | yes |
| workload | Workload name for resource names | `string` | n/a | yes |
| region_abbv | Abbreviated region code for resource naming | `string` | n/a | yes |
| aks_cluster_name | AKS cluster name (required if enable_aks_networking is true) | `string` | `null` | no |
| aks_subnet_name | Subnet name for AKS nodes | `string` | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| enable_aks_networking | Whether to configure AKS-specific networking (NSG rules, private DNS) | `bool` | `false` | no |
| enable_key_vault | Whether to create a Key Vault as part of the base stack | `bool` | `true` | no |
| key_vault_sku | Key Vault SKU (standard or premium) | `string` | `"standard"` | no |
| subnets | Subnet definitions (same schema as the networking module) | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    service_endpoints = optional(list(string), [])<br/>    delegation        = optional(map(list(map(string))), {})<br/>  }))</pre> | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| key_vault_id | Key Vault ID (null if key vault disabled) |
| key_vault_name | Key Vault name (null if key vault disabled) |
| key_vault_uri | Key Vault URI (null if key vault disabled) |
| kubernetes_subnet_id | Cloud-agnostic Kubernetes node subnet ID |
| location | Azure region of the stack |
| network_id | Cloud-agnostic network identifier |
| network_name | Cloud-agnostic network name |
| resource_group_id | ID of the created resource group |
| resource_group_name | Name of the created resource group |
| subnet_ids | Map of subnet names to IDs |
| vnet_id | Virtual network ID |
| vnet_name | Virtual network name |
<!-- END_TF_DOCS -->

## Dependencies

None -- this is a composite module that internally composes `resource_group`, `networking`, and `key_vault`.

## Notes

- Demonstrates the composite module pattern: small single-purpose modules wired together with explicit dependencies.
- Exposes cross-cloud interface outputs (`network_id`, `network_name`, `kubernetes_subnet_id`) so cloud-agnostic modules can consume its networking outputs.
- Key Vault creation is toggled independently via `enable_key_vault`.
