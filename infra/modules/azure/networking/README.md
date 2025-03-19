# Azure Networking Module

This module creates a virtual network infrastructure in Azure with customizable subnet configurations and network security groups. It now also includes integrated AKS networking support.

## Features

- Creates a resource group for networking resources
- Deploys a virtual network with configurable address space
- Creates multiple subnets with configurable address prefixes
- Configures service endpoints for each subnet
- Associates a network security group with each subnet
- Supports custom DNS servers
- Applies standardized tagging to all resources
- **AKS Networking Support**:
  - Creates private DNS zones for AKS private clusters
  - Configures AKS-specific NSG rules for node subnet security
  - Links private DNS zones to the virtual network
  - Optimizes network settings for AKS deployments

## Usage

### Basic Usage

```hcl
module "networking" {
  source = "../../modules/azure/networking"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  vnet_name           = "my-vnet"
  
  # VNet address space
  address_space = ["10.0.0.0/16"]
  
  # Subnets configuration
  subnets = {
    "app-subnet" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    },
    "data-subnet" = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
    }
  }
  
  # DNS configuration (optional)
  dns_servers = ["168.63.129.16"]
  
  # Tags (optional)
  tags = {
    Environment = "dev"
    Project     = "example"
  }
}
```

### With AKS Networking

```hcl
module "networking" {
  source = "../../modules/azure/networking"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  vnet_name           = "my-vnet"
  
  # VNet address space
  address_space = ["10.0.0.0/16"]
  
  # Subnets configuration
  subnets = {
    "az1-node-subnet" = {
      address_prefixes  = ["10.0.0.0/20"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    },
    "az1-pod-subnet" = {
      address_prefixes  = ["10.0.16.0/20"]
    },
    "az1-endpoint-subnet" = {
      address_prefixes  = ["10.0.32.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
  }
  
  # Enable AKS networking features
  enable_aks_networking = true
  aks_subnet_name = "az1-node-subnet"
  aks_cluster_name = "my-aks-cluster"
  aks_private_cluster_enabled = true
  aks_node_resource_group = "my-aks-nodes-rg"
  
  # Tags
  tags = {
    Environment = "dev"
    Project     = "example"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| resource_group_name | Name of the resource group to deploy the virtual network in | `string` | n/a | yes |
| location | Azure region where resources will be deployed | `string` | n/a | yes |
| vnet_name | Name of the virtual network to create | `string` | n/a | yes |
| address_space | Address space for the virtual network | `list(string)` | `["10.0.0.0/16"]` | no |
| subnets | Map of subnet names to configuration | `map(object)` | `{}` | no |
| dns_servers | List of DNS servers to use with the virtual network | `list(string)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| enable_aks_networking | Whether to enable AKS-specific networking features | `bool` | `false` | no |
| aks_subnet_name | Name of the subnet to use for AKS nodes. Must match a key in the subnets map. | `string` | `null` | no |
| aks_cluster_name | Name of the AKS cluster. Required if enable_aks_networking is true. | `string` | `null` | no |
| aks_private_cluster_enabled | Whether the AKS cluster is private. This affects DNS zone creation. | `bool` | `false` | no |
| aks_node_resource_group | Name of the resource group where AKS will create node resources | `string` | `null` | no |
| aks_private_dns_zone_id | ID of an existing private DNS zone for AKS. If not provided, a new one will be created if needed. | `string` | `null` | no |

### Subnet Configuration

The `subnets` input accepts a map of subnet configurations with the following structure:

```hcl
subnets = {
  "subnet-name" = {
    address_prefixes  = ["10.0.1.0/24"]  # Required
    service_endpoints = ["Microsoft.Storage"]  # Optional
    delegation        = {}  # Optional
  }
}
```

## Outputs

| Name | Description |
|------|-------------|
| vnet_id | The ID of the virtual network |
| vnet_name | The name of the virtual network |
| vnet_resource_group_name | The name of the resource group containing the virtual network |
| vnet_location | The location of the virtual network |
| vnet_address_space | The address space of the virtual network |
| subnet_ids | Map of subnet names to subnet IDs |
| nsg_ids | Map of subnet names to network security group IDs |
| aks_subnet_id | The ID of the subnet used for AKS nodes |
| aks_private_dns_zone_id | The ID of the AKS private DNS zone if created |
| aks_private_dns_zone_name | The name of the AKS private DNS zone if created |
| aks_nsg_id | The ID of the network security group attached to the AKS subnet |
| vnet_subnet_ids | List of all subnet IDs in the virtual network |
| private_endpoints_subnet_id | The ID of the private endpoints subnet if it exists |

## AKS Networking Features

### Network Security Group Rules

When AKS networking is enabled, the module adds the following NSG rules to the AKS subnet:

1. **AllowAzureLoadBalancer**: Permits traffic from Azure Load Balancer, which is essential for AKS functionality.
2. **DenyAllInbound**: A restrictive rule (priority 4096) that blocks unwanted inbound traffic by default.

### Private DNS Zones

For private AKS clusters, the module creates:

1. A private DNS zone with the name pattern: `privatelink.{region}.azmk8s.io`
2. A virtual network link that connects the DNS zone to your VNet

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

### Test Implementation

The tests use Terraform's built-in testing framework to validate:

1. **Unit Tests (Plan Only)**: These tests use `command = plan` to validate configuration logic without creating resources.
2. **Integration Tests (Optional)**: When run with proper credentials, the tests can deploy actual resources temporarily to validate functionality.

### CI/CD Integration

In the CI/CD pipeline, tests can be run in several modes:

1. **Plan-only mode**: For quick validation without resource creation
2. **Full test mode**: For complete validation with temporary resource creation (requires Azure credentials)

## License

This module is licensed under the MIT License. 