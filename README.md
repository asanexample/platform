# Multi-Cloud Platform Infrastructure

This repository contains infrastructure-as-code for a multi-cloud platform using Terraform and Terragrunt.

## Project Structure

```
platform/
├── infra/                   # Infrastructure code
│   ├── docs/                # Documentation
│   │   ├── cidr-allocation.md  # CIDR allocation strategy
│   │   └── NAMING_CONVENTIONS.md  # Naming conventions
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
│   │       ├── storage/            # Azure storage module
│   │       ├── storage_container/  # Azure container module
│   │       ├── terraform_state/    # Azure Terraform state module
│   │       └── hosting/            # Azure hosting module (networking + storage)
│   ├── tests/               # Test configurations
│   │   └── modules/         # Module tests
│   │       └── azure/       # Azure module tests
│   └── scripts/             # Utility scripts
├── REQUIREMENTS.md          # Project requirements
├── IMPLEMENTATION.md        # Implementation plan
└── NAMING_CONVENTIONS.md    # Naming conventions
```

## Features

- **Hierarchical CIDR Allocation**: Well-structured address space organization (see [CIDR Allocation Strategy](infra/docs/cidr-allocation.md))
- **Multi-Environment Support**: Separate configurations for dev, test, and production environments
- **Multi-Region Deployment**: Support for deploying to multiple Azure regions
- **Terragrunt Integration**: DRY approach using Terragrunt to manage common configurations
- **Terraform Module Testing**: Modules include automated tests to ensure functionality
- **Integrated Hosting Solution**: Combined networking and storage modules for application hosting

## Implemented Modules

The following modules have been implemented and tested:

1. **Azure Networking Module**
   - Creates virtual network with subnets optimized for Kubernetes workloads
   - Supports availability zone-aware subnet configuration
   - Configures network security groups with appropriate rules

2. **Azure Storage Module**
   - Provides flexible storage account creation with network rules
   - Supports different replication types based on environment needs
   - Configures lifecycle policies and access controls

3. **Azure Storage Container Module**
   - Creates and manages blob containers within storage accounts
   - Supports container-level access policies and metadata
   - Configures appropriate permissions for containers

4. **Azure Terraform State Module**
   - Specialized storage configuration optimized for Terraform state
   - Enforces best practices like versioning and proper retention policies
   - Configures secure access controls for state management

5. **Azure Hosting Module**
   - Combines networking and storage in a single module
   - Configures appropriate service endpoints for secure communication
   - Supports public and private container access with CORS configuration
   - Optimized for web application hosting

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

### Testing

To run tests for a module:

```bash
cd infra/modules/azure/networking
terraform test

# Run all tests for all modules
cd infra/tests
terraform test
```

## Contributing

Please follow these guidelines when contributing:

1. Use conventional commits for clear change history
2. Follow the established CIDR allocation strategy for network changes
3. Include tests for all new modules
4. Update documentation to reflect changes
5. Ensure all tests pass before submitting pull requests

## Documentation

- [Requirements](REQUIREMENTS.md) - Project requirements and specifications
- [Implementation Plan](IMPLEMENTATION.md) - Phased implementation approach
- [Naming Conventions](NAMING_CONVENTIONS.md) - Resource naming guidelines
- [CIDR Allocation](infra/docs/cidr-allocation.md) - Network addressing strategy

## License

This project is proprietary and confidential. 