# VIP Platform Naming Conventions

This document outlines the standard naming conventions used across the VIP Platform infrastructure to ensure consistency across all resources and environments.

## General Structure

Most resources follow this pattern:
```
vip-{customer}-{stage}-{resource_type}-{region_abbv}
```

Where:
- `vip` is our standard prefix
- `customer` is the customer name (lowercase, with special characters removed)
- `stage` is the environment (dev, preprod, prod)
- `resource_type` is a short abbreviation for the resource (see table below)
- `region_abbv` is the shortened region name (e.g., gwc, eus)

## Resource Type Abbreviations

| Resource Type | Abbreviation | Example |
|---------------|--------------|---------|
| Resource Group | rg | vip-customer-dev-rg-gwc |
| Key Vault | kv | vip-customer-dev-kv-gwc |
| Storage Account | sa | vipcustomerdevgwc (special format - see notes) |
| Workload Identity | workid | vip-customer-dev-workid-gwc |
| Federated Credential | fedcred | vip-customer-dev-fedcred-gwc |
| Storage Account Private Endpoint | sape | vip-customer-dev-sape-gwc |
| Storage Account Private Service Connection | sapsc | vip-customer-dev-sapsc-gwc |
| Virtual Network | vnet | vip-dev-vnet-gwc |
| Subnet | subnet | vip-dev-subnet-node-gwc |
| AKS Cluster | aks | vip-dev-aks-gwc |
| Front Door | fd | vip-dev-fd-gwc |
| Front Door Endpoint | fd-endpoint | vip-customer-dev-fd-endpoint-gwc |
| Front Door Origin Group | fd-og | vip-customer-dev-fd-og-gwc |
| Front Door Origin | fd-origin | vip-customer-dev-fd-origin-gwc |
| Front Door Route | fd-route | vip-customer-dev-fd-route-gwc |

## Special Notes

### Storage Accounts
Storage accounts have a 24 character limit and cannot use hyphens. They follow this pattern:
```
vip{customer}{stage}sa{region_abbv}
```

Example: `vipcustomerdevgwc`

### Container Names
Container names are consistent across all deployments:
- assets
- public
- pdf

### Deployment ID
The `deployment_id` variable is used primarily for Kubernetes namespace naming in workload identity federation. It is separate from the resource naming convention.

## Parameter Usage

These variables should be consistently used in modules:

- `customer`: The customer name (for resource naming and tagging)
- `stage`: The environment stage (dev, preprod, prod)
- `region_name`: Full region name
- `region_abbv`: Abbreviated region name

## Examples

### Resource Group
```
vip-customer-dev-rg-gwc
```

### Storage Account with Private Endpoint
```
vipcustomerdevsagwc
vip-customer-dev-sape-gwc
vip-customer-dev-sapsc-gwc
```

### AKS and Related Resources
```
vip-dev-aks-gwc
vip-dev-subnet-node-gwc
```

### Workload Identity Resources
```
vip-customer-dev-workid-gwc
vip-customer-dev-fedcred-gwc
```

## Implementation in Terraform

Always use locals to construct resource names following these conventions:

```hcl
locals {
  prefix = "vip"
  normalized_customer = lower(replace(var.customer, "/[^a-zA-Z0-9]/", ""))
  
  # Resource Group
  resource_group_name = "${local.prefix}-${var.customer}-${var.stage}-rg-${var.region_abbv}"
  
  # Storage Account (no hyphens, 24 char limit)
  storage_account_name = "${local.prefix}${local.normalized_customer}${var.stage}sa${var.region_abbv}"
}
``` 