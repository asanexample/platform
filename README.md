# Multi-Cloud Platform Infrastructure

This repository contains infrastructure-as-code for a multi-cloud platform using Terraform and Terragrunt, with a focus on security, reusability, and consistent implementation patterns.

## Project Structure

```
platform/
├── infra/                   # Infrastructure code
│   ├── docs/                # Documentation
│   │   ├── cidr-allocation.md  # CIDR allocation strategy
│   │   ├── naming-conventions.md  # Naming conventions
│   │   ├── network-topology.md  # Network topology documentation
│   │   └── multi-region-deployment.md  # Multi-region deployment guide
│   ├── live/                # Live infrastructure code (Terragrunt)
│   │   ├── _envcommon/      # Common environment configurations
│   │   └── azure/           # Azure-specific configurations
│   │       └── dev/         # Development environment
│   │           ├── eastus/  # East US region
│   │           │   ├── networking/  # Network infrastructure
│   │           │   └── hosting/     # Hosting infrastructure
│   │           └── westus/  # West US region
│   │               ├── networking/  # Network infrastructure
│   │               └── hosting/     # Hosting infrastructure
│   ├── modules/             # Reusable Terraform modules
│   │   └── azure/           # Azure-specific modules
│   │       ├── networking/         # Azure networking module
│   │       ├── storage_account/    # Azure storage account module
│   │       ├── storage_container/  # Azure container module
│   │       ├── key_vault/          # Azure Key Vault module
│   │       ├── naming/             # Azure resource naming module
│   │       ├── terraform_state/    # Azure Terraform state module
│   │       ├── hosting/            # Azure hosting module (networking + storage)
│   │       ├── aks_core/           # Azure AKS core cluster module
│   │       ├── aks_cluster/        # Azure AKS cluster module
│   │       ├── aks_cluster_composite/  # Azure AKS composite module
│   │       ├── aks_identity/       # Azure AKS identity module
│   │       ├── aks_networking/     # Azure AKS networking module
│   │       ├── aks_node_pools/     # Azure AKS node pools module
│   │       └── identities/         # Azure identities module
│   ├── tests/               # Test configurations
│   │   └── modules/         # Module tests
│   │       └── azure/       # Azure module tests
│   │           ├── networking/      # Networking module tests
│   │           ├── storage_account/ # Storage account module tests
│   │           ├── storage_container/ # Container module tests
│   │           ├── key_vault/       # Key Vault module tests
│   │           ├── naming/          # Naming module tests
│   │           ├── hosting/         # Hosting module tests
│   │           ├── aks_core/        # AKS core module tests
│   │           ├── aks_identity/    # AKS identity module tests
│   │           └── aks_networking/  # AKS networking module tests
│   └── scripts/             # Utility scripts
├── run_all_terraform_tests.sh  # Script to run all Terraform tests
├── REQUIREMENTS.md          # Project requirements
├── IMPLEMENTATION.md        # Implementation plan
└── NAMING_CONVENTIONS.md    # Naming conventions
```

## Features

- **Hierarchical CIDR Allocation**: Well-structured address space organization (see [CIDR Allocation Strategy](infra/docs/cidr-allocation.md))
- **Multi-Environment Support**: Separate configurations for dev, test, and production environments
- **Multi-Region Deployment**: Support for deploying to multiple Azure regions
- **Terragrunt Integration**: DRY approach using Terragrunt to manage common configurations
- **Comprehensive Testing**: All modules include automated tests with a unified test runner
- **Security Best Practices**: Implementation of cloud provider security recommendations
- **Standardized Naming**: Consistent resource naming across all environments
- **Integrated Hosting Solution**: Combined networking and storage modules for application hosting
- **AKS Cluster Support**: Kubernetes cluster deployment with multi-AZ node pools and workload identity

## Implemented Modules

The following modules have been implemented and tested:

1. **Azure Networking Module**
   - Creates virtual network with subnets optimized for Kubernetes workloads
   - Supports availability zone-aware subnet configuration
   - Configures network security groups with appropriate rules
   - Implements service endpoints for secure service connections
   - Supports custom DNS servers and address spaces

2. **Azure Storage Account Module**
   - Provides flexible storage account creation with network rules
   - Supports different replication types based on environment needs
   - Configures lifecycle policies and access controls
   - Implements network security rules for limiting access
   - Compatible with private endpoints for secure access

3. **Azure Storage Container Module**
   - Creates and manages blob containers within storage accounts
   - Supports container-level access policies and metadata
   - Configures appropriate permissions for containers
   - Allows customization of access types (private, blob, container)
   - Supports metadata tagging for organization

4. **Azure Key Vault Module**
   - Creates and configures Azure Key Vault with flexible options
   - Supports both RBAC and access policy authorization models
   - Configurable network rules and private endpoint integration
   - Implements security best practices like purge protection and soft delete
   - Auto-generates names following organization naming conventions

5. **Azure Naming Module**
   - Generates standardized resource names following organizational patterns
   - Supports customer-specific and shared resource naming
   - Handles special cases for resources with specific naming requirements
   - Ensures compliance with Azure naming restrictions
   - Provides consistent outputs for all resource types

6. **Azure Terraform State Module**
   - Specialized storage configuration optimized for Terraform state
   - Enforces best practices like versioning and proper retention policies
   - Configures secure access controls for state management
   - Supports locking for collaborative environments
   - Implements backup and recovery mechanisms

7. **Azure Hosting Module**
   - Combines networking, storage, and key vault in a single module
   - Configures appropriate service endpoints for secure communication
   - Supports public and private container access with CORS configuration
   - Integrates key vault with network security and access controls
   - Optimized for web application hosting
   - Integrates with naming conventions for consistent resource naming

8. **Azure AKS Core Module**
   - Configures core Kubernetes cluster resources
   - Implements secure default configurations
   - Supports integration with Azure CNI networking
   - Configures monitoring and logging
   - Implements RBAC and Azure AD integration

9. **Azure AKS Cluster Composite Module**
   - Combines multiple AKS modules for simplified deployment
   - Integrates core cluster, identity, networking, and node pools
   - Provides a unified interface for complete AKS deployment
   - Implements secure defaults and best practices
   - Supports customization of all cluster components

10. **Azure AKS Identity Module**
    - Configures service principals or managed identities for AKS
    - Implements workload identity federation
    - Sets up appropriate RBAC permissions
    - Integrates with Azure AD groups
    - Supports pod-level identity assignments

11. **Azure AKS Networking Module**
    - Configures AKS-specific network resources
    - Implements kubenet or Azure CNI networking
    - Configures network policies and security
    - Sets up appropriate DNS configuration
    - Supports advanced networking features like network policy

12. **Azure AKS Node Pools Module**
    - Creates and configures node pools across availability zones
    - Supports system and user node pools
    - Configures auto-scaling and node sizes
    - Implements taints and labels for workload assignment
    - Supports spot instances for cost optimization

## Network Design

The network architecture follows a Kubernetes-optimized design with:

- Hierarchical CIDR allocation for clear organizational boundaries
- 3-AZ design in each region for high availability
- Specialized subnet types per AZ for different workload requirements:
  - Node subnets for Kubernetes worker nodes
  - Load balancer subnets for ingress/egress
  - Endpoint subnets for private service connections
  - Transit subnets for connectivity between networks

## Getting Started

### Prerequisites

- Terraform >= 1.6.0
- Terragrunt >= 0.53.0
- Azure CLI with authenticated session

### Environment Setup

Set the required environment variables for Azure authentication:

```bash
export ARM_CLIENT_ID="your-client-id"
export ARM_CLIENT_SECRET="your-client-secret"
export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
```

Alternatively, authenticate using Azure CLI:

```bash
az login
az account set --subscription "your-subscription-id"
```

### Deployment

To deploy the infrastructure, navigate to the specific environment directory and run Terragrunt:

```bash
# Deploy networking in East US dev environment
cd infra/live/azure/dev/eastus/networking
terragrunt apply

# Deploy hosting in East US dev environment 
cd infra/live/azure/dev/eastus/hosting
terragrunt apply
```

To deploy all components in an environment:

```bash
cd infra/live/azure/dev/eastus
terragrunt run-all apply
```

## Testing

All modules include comprehensive tests to validate functionality and ensure quality. Tests use Terraform's built-in testing framework and are designed to run without creating actual resources.

### Running Tests

To run tests for a specific module:

```bash
cd infra/tests/modules/azure/networking
terraform init
terraform test
```

To run all tests across all modules using our automated test script:

```bash
# From the project root
./run_all_terraform_tests.sh
```

The test script will:
- Automatically run tests for all Azure modules
- Initialize Terraform in each test directory if needed
- Provide a summary of test results (pass/fail)
- Exit with appropriate code for CI/CD integration

### Test Coverage

Our tests cover:
- Basic resource creation
- Complex configurations
- Edge cases and validation rules
- Integration between components
- Naming convention compliance
- Security best practices

## Security Practices

This infrastructure implements the following security practices:

- **Network Segmentation**: Proper VNET and subnet isolation
- **Least Privilege Access**: RBAC configurations follow principle of least privilege
- **Data Encryption**: Storage accounts and Key Vaults configured with encryption
- **Secret Management**: Key Vault used for secure secret storage
- **Network Access Controls**: Default-deny with explicit allow lists
- **Private Endpoints**: Used for secure access to PaaS services
- **Workload Identity Federation**: Secure pod-level authentication without stored credentials
- **Compliance Validation**: Tests verify security configurations

## Documentation

Detailed documentation is available in the `/infra/docs` directory:

- [Naming Conventions](infra/docs/naming-conventions.md) - Resource naming standards
- [CIDR Allocation](infra/docs/cidr-allocation.md) - Network addressing strategy
- [Network Topology](infra/docs/network-topology.md) - Network design documentation
- [Multi-Region Deployment](infra/docs/multi-region-deployment.md) - Guide for multi-region deployments

## Contributing

Please follow these guidelines when contributing:

1. **Code Quality**:
   - Use conventional commits for clear change history (feat, fix, docs, etc.)
   - Follow established coding patterns in existing modules
   - Ensure all variables have proper validation and descriptions
   - Include inline comments for complex logic

2. **Testing**:
   - Add tests for all new functionality
   - Ensure all existing tests pass before submitting PR
   - Use the test runner script to validate all modules
   - Write both basic and advanced configuration tests

3. **Documentation**:
   - Update module README.md with any changes
   - Document all input and output variables
   - Include usage examples for common scenarios
   - Update main documentation if adding new modules

4. **Network Changes**:
   - Follow the established CIDR allocation strategy
   - Document any deviations from standard allocations
   - Ensure network changes don't break existing connectivity
   - Verify network security groups maintain proper protection

## License

This project is proprietary and confidential.

## Makefile Usage

A Makefile is provided at the root of the repository to simplify common operations:

### Basic Usage

```bash
# Show all available commands
make help

# Initialize all modules in Azure dev westus region (default)
make init

# Plan all modules in Azure dev westus region (default)
make plan

# Apply all modules in Azure dev westus region (default)
make apply
```

### Working with Different Environments, Regions, and Clouds

```bash
# Initialize modules in a specific environment/region/cloud
make init ENV=prod REGION=eastus CLOUD=azure

# Plan a specific environment
make plan ENV=staging

# Apply changes to a specific cloud/environment/region
make apply CLOUD=aws ENV=dev REGION=us-east-1
```

### Working with Specific Modules

```bash
# Initialize a specific module
make init-module MODULE=networking

# Plan a specific module
make plan-module MODULE=aks

# Apply a specific module
make apply-module MODULE=keyvault
```

### Cleaning Up

```bash
# Clean Terragrunt cache for current environment/region
make clean

# Clean all Terragrunt cache
make clean-all
```

### Listing Available Options

```bash
# List available cloud providers
make list-clouds

# List available environments for the current cloud
make list-envs

# List available regions for the current cloud/environment
make list-regions

# List available modules for the current cloud/environment/region
make list-modules
``` 