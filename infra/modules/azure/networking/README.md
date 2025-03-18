# Azure Networking Module

This module creates a virtual network infrastructure in Azure with customizable subnet configurations and network security groups.

## Features

- Creates a resource group for networking resources
- Deploys a virtual network with configurable address space
- Creates multiple subnets with configurable address prefixes
- Configures service endpoints for each subnet
- Associates a network security group with each subnet
- Supports custom DNS servers
- Applies standardized tagging to all resources

## Usage

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