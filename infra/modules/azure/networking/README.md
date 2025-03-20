# Azure Networking Module

This module creates the core Azure networking components including virtual networks, subnets, and network security groups for AKS and related services.

## Features

- Creates a Virtual Network with configurable address space
- Creates multiple subnets with associated Network Security Groups
- Configurable subnet delegations and service endpoints
- Support for private endpoints and DNS zones
- Compatible with Cilium CNI deployment on AKS

## Usage

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  # VNet configuration
  name          = "vip-vnet-dev-eus-main"
  address_space = ["10.0.0.0/16"]
  
  # Subnet configuration
  subnets = {
    "az1-nodes" = {
      address_prefix = "10.0.0.0/24"
      security_rules = local.node_subnet_rules
    },
    "az2-nodes" = {
      address_prefix = "10.0.10.0/24"
      security_rules = local.node_subnet_rules
    },
    "az3-nodes" = {
      address_prefix = "10.0.20.0/24"
      security_rules = local.node_subnet_rules
    },
    "endpoints" = {
      address_prefix = "10.0.30.0/24"
      security_rules = local.endpoint_subnet_rules
    }
  }
  
  # DNS servers (optional)
  dns_servers = null # Use Azure-provided DNS
  
  # Create private DNS zone for AKS
  create_private_dns_zone = true
  private_dns_zone_name   = "privatelink.eastus.azmk8s.io"
  
  # Apply tags
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Subnet Configuration for Cilium CNI

When using Cilium as the CNI for AKS, consider the following subnet configurations:

1. **Node Subnet Sizing**: Since Cilium uses its own IPAM (IP Address Management) and not Azure CNI, you can allocate smaller subnet sizes for nodes. Cilium manages pod IPs independently of the Azure subnet.

2. **Security Rules**: Ensure the Node Subnet NSGs allow the following traffic:
   - Inbound from other node subnets (for pod-to-pod communication)
   - Outbound to all destinations 
   - Inbound from Azure Load Balancer

3. **MTU Considerations**: Cilium operates efficiently with an MTU of 1450, which works well with Azure's underlying infrastructure.

Example NSG rules for Cilium compatibility:

```hcl
locals {
  node_subnet_rules = [
    {
      name                       = "AllowAzureLoadBalancerInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowClusterCommunication"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | The name of the resource group | `string` | n/a | yes |
| location | The Azure region where resources will be created | `string` | n/a | yes |
| name | The name of the virtual network | `string` | n/a | yes |
| address_space | The address space for the virtual network | `list(string)` | n/a | yes |
| subnets | Map of subnet configurations | `map(object)` | `{}` | no |
| dns_servers | List of DNS servers to use for the virtual network | `list(string)` | `null` | no |
| create_private_dns_zone | Whether to create a private DNS zone for AKS | `bool` | `false` | no |
| private_dns_zone_name | The name of the private DNS zone for AKS | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the virtual network |
| name | The name of the virtual network |
| resource_group_name | The name of the resource group containing the virtual network |
| address_space | The address space of the virtual network |
| subnet_ids | Map of subnet names to their respective IDs |
| private_dns_zone_id | The ID of the private DNS zone for AKS (if created) |
| network_security_group_ids | Map of NSG names to their respective IDs |

## Notes

- Network Security Groups are created per subnet with configurable rules
- The module supports creation of an AKS private DNS zone for private clusters
- Subnet NSG rules can be customized for different workloads
- Compatible with the Azure CNI networking plugin for AKS, and optimized for subsequent Cilium CNI installation

## Testing

This module includes Terraform tests that validate the module's functionality:

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
# Run tests in the module directory
terraform test
```

The tests validate:
- Correct resource creation
- Proper configuration of virtual networks and subnets
- Correct association of network security groups
- Proper handling of multiple subnet configurations

### CI/CD Integration

In the CI/CD pipeline, tests can be run in several modes:

1. **Plan-only mode**: For quick validation without resource creation
2. **Full test mode**: For complete validation with temporary resource creation (requires Azure credentials)

## License

This module is licensed under the MIT License. 