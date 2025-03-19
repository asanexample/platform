# Multi-Cloud Platform Infrastructure

This repository contains infrastructure-as-code for a multi-cloud platform using Terraform and Terragrunt, with a focus on security, reusability, and consistent implementation patterns.

## Project Structure

```
platform/
├── infra/                   # Infrastructure code
│   ├── docs/                # Documentation
│   │   ├── 00-documentation-guide.md  # Documentation standards
│   │   ├── 01-introduction.md         # Project introduction
│   │   ├── 02-architecture-overview.md # Architecture overview
│   │   ├── ...                        # Additional documentation
│   │   └── README.md                  # Documentation index
│   ├── live/                # Live infrastructure code (Terragrunt)
│   │   └── azure/           # Azure-specific configurations
│   │       └── dev/         # Development environment
│   │           └── westus/  # West US region
│   │               ├── aks_core/      # AKS cluster core
│   │               ├── aks_identity/  # AKS managed identities
│   │               ├── aks_node_pools/ # AKS node pools
│   │               ├── key_vault/     # Azure Key Vault
│   │               ├── naming/        # Resource naming
│   │               ├── networking/    # Network infrastructure
│   │               ├── resource_group/ # Resource groups
│   │               └── storage/       # Storage accounts and containers
│   ├── modules/             # Reusable Terraform modules
│   │   └── azure/           # Azure-specific modules
│   │       ├── aks_core/            # Azure AKS core cluster module
│   │       ├── aks_identity/        # Azure AKS identity module
│   │       ├── aks_node_pools/      # Azure AKS node pools module
│   │       ├── hosting/             # Azure hosting module
│   │       ├── identities/          # Azure identities module
│   │       ├── key_vault/           # Azure Key Vault module
│   │       ├── naming/              # Azure resource naming module
│   │       ├── networking/          # Azure networking module
│   │       ├── resource_group/      # Azure resource group module
│   │       ├── storage_account/     # Azure storage account module
│   │       ├── storage_container/   # Azure container module
│   │       └── terraform_state/     # Azure Terraform state module
│   ├── terragrunt.hcl       # Root Terragrunt configuration
│   └── tests/               # Test configurations
│       └── modules/         # Module tests
│           └── azure/       # Azure module tests
│               ├── aks_core/         # AKS core module tests
│               ├── aks_node_pools/   # AKS node pools module tests
│               ├── hosting/          # Hosting module tests
│               ├── identities/       # Identities module tests
│               ├── key_vault/        # Key Vault module tests
│               ├── naming/           # Naming module tests
│               ├── networking/       # Networking module tests
│               └── storage_account/  # Storage account module tests
├── Makefile                 # Infrastructure operations automation
├── run_all_terraform_tests.sh # Script to run all Terraform tests
└── IMPLEMENTATION.md        # Implementation plan
```

## Features

- **Hierarchical CIDR Allocation**: Well-structured address space organization (see [CIDR Allocation Strategy](infra/docs/06-cidr-allocation.md))
- **Multi-Environment Support**: Configurable for development, test, and production environments
- **Multi-Region Deployment**: Support for deploying to multiple Azure regions
- **Terragrunt Integration**: DRY approach using Terragrunt to manage common configurations
- **Comprehensive Testing**: Modules include automated tests in a dedicated tests directory
- **Security Best Practices**: Implementation of Azure security recommendations
- **Standardized Naming**: Consistent resource naming across all environments
- **AKS Cluster Support**: Kubernetes cluster deployment with node pools and workload identity

## Core Modules

The platform includes the following core modules:

1. **Azure Networking Module**
   - Creates virtual network with subnets optimized for Kubernetes workloads
   - Supports availability zone-aware subnet configuration
   - Configures network security groups with appropriate rules

2. **Azure Storage Account Module**
   - Provides flexible storage account creation with network rules
   - Supports different replication types based on environment needs
   - Configures access controls and container management

3. **Azure Key Vault Module**
   - Creates and configures Azure Key Vault with flexible options
   - Supports RBAC authorization model
   - Configurable network rules and security settings

4. **Azure AKS Modules**
   - **AKS Core**: Creates and configures the core Kubernetes cluster
   - **AKS Identity**: Manages service identities for Kubernetes
   - **AKS Node Pools**: Creates and configures node pools for workloads

5. **Azure Naming Module**
   - Generates standardized resource names following organizational patterns
   - Ensures compliance with Azure naming restrictions
   - Provides consistent outputs for all resource types

## Getting Started

### Prerequisites

- Terraform >= 1.6.0
- Terragrunt >= 0.53.0
- Azure CLI with authenticated session

### Environment Setup

Authenticate using Azure CLI:

```bash
az login
az account set --subscription "your-subscription-id"
```

### Deployment

The project includes a comprehensive Makefile to simplify operations:

```bash
# Initialize all modules
make init

# Plan all modules
make plan

# Apply all modules
make apply
```

Working with specific modules:

```bash
# Initialize a specific module
make init-module MODULE=networking

# Plan a specific module
make plan-module MODULE=aks_core

# Apply a specific module
make apply-module MODULE=key_vault
```

Environment configuration:

```bash
# Work with different environments/regions
make plan ENV=prod REGION=eastus
```

## Testing

Module tests are organized in the `infra/tests/modules/` directory, separate from the module code. This ensures clear separation between implementation and testing.

Run all tests with:

```bash
make test
```

To run tests for a specific module:

```bash
make test-module MODULE=networking
```

## Documentation

Detailed documentation is available in the `/infra/docs` directory:

- [Documentation Guide](infra/docs/00-documentation-guide.md)
- [Project Introduction](infra/docs/01-introduction.md)
- [Architecture Overview](infra/docs/02-architecture-overview.md)
- [Infrastructure as Code Approach](infra/docs/03-infrastructure-as-code.md)
- [CIDR Allocation Strategy](infra/docs/06-cidr-allocation.md)
- [Naming Conventions](infra/docs/11-naming-conventions.md)

For a complete list of documentation, see the [Documentation Table of Contents](infra/docs/README.md).

## Makefile Commands

The Makefile provides the following commands:

```bash
# Basic operations
make init                # Initialize all modules
make plan                # Plan all modules
make apply               # Apply all modules
make validate            # Validate all modules
make clean               # Clean Terragrunt cache

# Module-specific operations
make init-module         # Initialize a specific module
make plan-module         # Plan a specific module
make apply-module        # Apply a specific module

# Advanced operations
make init-upgrade        # Initialize with dependency upgrades
make show-outputs        # Show outputs for all modules
make show-state          # Show state for all modules
```

For a complete list of commands, run `make help`. 