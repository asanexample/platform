/**
 * # Azure Networking Module
 *
 * This module creates an Azure virtual network with subnets and network security groups.
 * It also supports AKS-specific networking features when enabled.
 */

## Overview

This module creates core Azure networking components for cloud infrastructure, with specific optimizations for Azure Kubernetes Service (AKS) deployments. It implements a secure, scalable network architecture with virtual networks, subnets, and network security groups designed for enterprise workloads.

## Features

- Creates a Virtual Network with configurable address space and DNS settings
- Provisions multiple subnets with associated Network Security Groups (NSGs)
- Supports custom subnet delegations and service endpoints
- Enables private DNS zone integration for AKS private clusters
- Availability zone-aware subnet design for high availability
- Compatible with both Azure CNI and Cilium CNI for AKS
- Comprehensive security rules with customizable network policies

## Usage

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  # VNet configuration
  name          = "vnet-platform-prod-eastus"
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
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Networking"
  }
}
```

## Examples

### Basic Development Network

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name          = "vnet-platform-dev-eastus"
  address_space = ["10.1.0.0/16"]
  
  subnets = {
    "aks-nodes" = {
      address_prefix = "10.1.0.0/22"
      security_rules = local.basic_security_rules
    },
    "services" = {
      address_prefix = "10.1.4.0/24"
    }
  }
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production AKS Network with Cilium CNI Support

```hcl
locals {
  cilium_node_rules = [
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

module "networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name          = "vnet-platform-prod-eastus"
  address_space = ["10.0.0.0/16"]
  
  subnets = {
    "az1-nodes" = {
      address_prefix = "10.0.0.0/24"
      security_rules = local.cilium_node_rules
    },
    "az2-nodes" = {
      address_prefix = "10.0.1.0/24"
      security_rules = local.cilium_node_rules
    },
    "az3-nodes" = {
      address_prefix = "10.0.2.0/24"
      security_rules = local.cilium_node_rules
    },
    "endpoints" = {
      address_prefix = "10.0.10.0/24"
      security_rules = []
      service_endpoints = [
        "Microsoft.Storage",
        "Microsoft.KeyVault",
        "Microsoft.ContainerRegistry"
      ]
    }
  }
  
  create_private_dns_zone = true
  private_dns_zone_name   = "privatelink.eastus.azmk8s.io"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Networking"
    CNI         = "Cilium"
  }
}
```

### Hub Network for Hub-Spoke Topology

```hcl
module "hub_networking" {
  source = "../../modules/azure/networking"
  
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name          = "vnet-hub-prod-eastus"
  address_space = ["10.100.0.0/16"]
  
  subnets = {
    "gateway" = {
      address_prefix = "10.100.0.0/24"
    },
    "firewall" = {
      address_prefix = "10.100.1.0/24"
    },
    "bastion" = {
      address_prefix = "10.100.2.0/24"
    }
  }
  
  # Custom DNS servers (e.g., for Active Directory)
  dns_servers = ["10.100.10.4", "10.100.10.5"]
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Hub"
    Network     = "Core"
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
| resource_group_name | The name of the resource group where the network resources will be created | `string` |
| location | The Azure region where the network resources will be deployed | `string` |
| name | The name of the virtual network | `string` |
| address_space | The address space for the virtual network | `list(string)` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| subnets | Map of subnet configurations with address prefixes and security rules | `map(object)` | `{}` | no |
| dns_servers | Custom DNS servers to use for the virtual network | `list(string)` | `null` | no |
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

## Module Resources

This module creates the following resources:
- Azure Virtual Network
- Azure Subnets
- Network Security Groups
- Private DNS Zone (optional)

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation

## Subnet Configuration for Cilium CNI

When using Cilium as the CNI for AKS, consider the following subnet configurations:

1. **Node Subnet Sizing**: Since Cilium uses its own IPAM (IP Address Management) and not Azure CNI, you can allocate smaller subnet sizes for nodes. Cilium manages pod IPs independently of the Azure subnet.

2. **Security Rules**: Ensure the Node Subnet NSGs allow the following traffic:
   - Inbound from other node subnets (for pod-to-pod communication)
   - Outbound to all destinations 
   - Inbound from Azure Load Balancer

3. **MTU Considerations**: Cilium operates efficiently with an MTU of 1450, which works well with Azure's underlying infrastructure.

## Network Security Best Practices

For production environments, consider implementing the following security best practices:

1. **Micro-segmentation**: Create dedicated subnets for different workload types with appropriate security rules
2. **Private Links**: Use private endpoints for Azure services to avoid exposing traffic to the public internet
3. **Service Endpoints**: Enable service endpoints on subnets that need to access Azure services
4. **Network Flow Logs**: Enable network watcher flow logs for traffic analysis
5. **Firewall**: For hub-spoke topologies, implement Azure Firewall in the hub network

## Testing

This module includes Terraform tests that validate the module's functionality:

### Prerequisites for Testing

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

## Notes

- Network Security Groups are created per subnet with configurable rules
- The module supports creation of an AKS private DNS zone for private clusters
- Subnet NSG rules can be customized for different workloads
- For AKS deployments, consider the node pool subnet size requirements based on CNI type
- For Cilium CNI, smaller subnets can be used as pod IPs are managed by Cilium
- Consider service endpoints for connecting to Azure services securely
- For private AKS clusters, ensure the private DNS zone is correctly configured

## License

This module is licensed under the MIT License.

## AKS Network Security Group Rules

When `enable_aks_networking` is set to `true` and `aks_subnet_name` is provided, the module will automatically
create the following network security group rules:

1. **AllowAzureLoadBalancer**: Allows inbound traffic from Azure Load Balancer
2. **DenyAllInbound**: Denies all other inbound traffic (lowest priority rule)
3. **AllowCiliumHealth**: Allows TCP port 4240 for Cilium agent health checks
4. **AllowVXLAN**: Allows UDP port 8472 for VXLAN overlay networking (used by Cilium)
5. **AllowNodeCommunication**: Allows traffic between all Kubernetes subnets (essential for multi-AZ clusters)

The Cilium-specific rules are required for proper functioning of the Cilium CNI in AKS clusters,
especially when using the network_plugin = "none" setting and installing Cilium as the CNI provider.
Without these rules, Cilium components may experience TLS handshake failures and communication issues. 