# Multi-Cloud Platform Infrastructure

This repository contains infrastructure-as-code for a multi-cloud platform using Terraform and Terragrunt, with a focus on security, reusability, and consistent implementation patterns.

## Current Implementation Status

The project is currently in active development with the following status:

- **Azure Implementation**: 
  - Core modules implemented (networking, storage, AKS, Key Vault, identity)
  - Monitoring modules implemented (Log Analytics, Monitor Workspace, Prometheus DCR)
  - Frontend modules implemented (Front Door Profile, Endpoint, Private Link)
  - Container Registry and related services implemented
- **AWS Implementation**: Planned for future phases
- **GCP Implementation**: Planned for future phases
- **Development Environment**: Implemented for Azure in East US region
- **Operations Environment**: Implemented for Azure in West US region
- **Production Environment**: Planned for future phases

The implementation is following the phased approach defined in [IMPLEMENTATION.md](IMPLEMENTATION.md).

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
│   │       ├── _envcommon/  # Common configurations across environments
│   │       ├── dev/         # Development environment
│   │       │   └── eastus/  # East US region
│   │       │       ├── aks_core/             # AKS cluster core
│   │       │       ├── aks_identity/         # AKS managed identities
│   │       │       ├── aks_node_pools/       # AKS node pools
│   │       │       ├── client_config/        # Azure client configuration
│   │       │       ├── container_registry/   # Container registry
│   │       │       ├── dns/                  # Private DNS zones
│   │       │       ├── frontdoor_endpoint/   # Front Door endpoints
│   │       │       ├── frontdoor_private_link/ # Front Door private link
│   │       │       ├── frontdoor_profile/    # Front Door profile
│   │       │       ├── key_vault/            # Azure Key Vault
│   │       │       ├── log_analytics/        # Log Analytics workspace
│   │       │       ├── managed_grafana/      # Managed Grafana
│   │       │       ├── monitor_workspace/    # Monitor workspace for Prometheus
│   │       │       ├── naming/               # Resource naming
│   │       │       ├── networking/           # Network infrastructure
│   │       │       ├── prometheus_dcr/       # Prometheus data collection rule
│   │       │       ├── resource_group/       # Resource groups
│   │       │       ├── storage/              # Storage accounts and containers
│   │       │       └── storage_roles/        # Storage account RBAC
│   │       └── ops/         # Operations environment
│   │           └── westus/  # West US region
│   │               ├── aks_core/             # AKS cluster core
│   │               ├── aks_identity/         # AKS managed identities
│   │               ├── aks_node_pools/       # AKS node pools
│   │               ├── client_config/        # Azure client configuration
│   │               ├── container_registry/   # Container registry
│   │               ├── dns/                  # Private DNS zones
│   │               ├── frontdoor_endpoint/   # Front Door endpoints
│   │               ├── frontdoor_private_link/ # Front Door private link
│   │               ├── frontdoor_profile/    # Front Door profile
│   │               ├── key_vault/            # Azure Key Vault
│   │               ├── log_analytics/        # Log Analytics workspace
│   │               ├── managed_grafana/      # Managed Grafana
│   │               ├── monitor_workspace/    # Monitor workspace for Prometheus
│   │               ├── naming/               # Resource naming
│   │               ├── networking/           # Network infrastructure
│   │               ├── resource_group/       # Resource groups
│   │               ├── storage/              # Storage accounts and containers
│   │               └── storage_roles/        # Storage account RBAC
│   ├── modules/             # Reusable Terraform modules
│   │   └── azure/           # Azure-specific modules
│   │       ├── aks_core/              # Azure AKS core cluster module
│   │       ├── aks_identity/          # Azure AKS identity module
│   │       ├── aks_node_pools/        # Azure AKS node pools module
│   │       ├── client_config/         # Azure client configuration module
│   │       ├── container_registry/    # Azure Container Registry module
│   │       ├── frontdoor_endpoint/    # Front Door endpoint module
│   │       ├── frontdoor_private_link/ # Front Door private link module
│   │       ├── frontdoor_profile/     # Front Door profile module
│   │       ├── identities/            # Azure identities module
│   │       ├── key_vault/             # Azure Key Vault module
│   │       ├── log_analytics/         # Log Analytics workspace module
│   │       ├── managed_grafana/       # Managed Grafana module
│   │       ├── monitor_workspace/     # Monitor workspace module
│   │       ├── naming/                # Azure resource naming module
│   │       ├── networking/            # Azure networking module
│   │       ├── private_dns/           # Private DNS zones module
│   │       ├── prometheus_dcr/        # Prometheus data collection rule module
│   │       ├── resource_group/        # Azure resource group module
│   │       ├── storage_account/       # Azure storage account module
│   │       ├── storage_container/     # Azure container module
│   │       └── storage_roles/         # Storage account RBAC module
│   ├── terragrunt.hcl       # Root Terragrunt configuration
│   └── tests/               # Test configurations
│       ├── helpers/         # Test helper functions
│       ├── modules/         # Module tests
│       │   └── azure/       # Azure module tests
│       └── setup/           # Test setup configurations
├── Makefile                 # Infrastructure operations automation
├── scripts/                 # Utility scripts for the repository
└── IMPLEMENTATION.md        # Implementation plan
```

## Features

- **Hierarchical CIDR Allocation**: Well-structured address space organization (see [CIDR Allocation Strategy](infra/docs/06-cidr-allocation.md))
- **Multi-Environment Support**: Configurable for development, operations, and production environments
- **Multi-Region Deployment**: Support for deploying to multiple Azure regions (East US, West US)
- **Terragrunt Integration**: DRY approach using Terragrunt to manage common configurations
- **Comprehensive Testing**: Modules include automated tests in a dedicated tests directory
- **Security Best Practices**: Implementation of Azure security recommendations including private endpoints
- **Standardized Naming**: Consistent resource naming across all environments via a dedicated naming module
- **AKS Cluster Support**: Kubernetes cluster deployment with node pools and workload identity
- **Monitoring & Observability**: Integrated monitoring with Log Analytics, Prometheus, and Grafana
- **Front Door Integration**: Global content delivery and security with Azure Front Door
- **Private Network Topology**: Private networking with private endpoints for enhanced security
- **Standardized Documentation**: Comprehensive documentation with standardized templates

## Core Modules

The platform includes the following core modules:

1. **Azure Resource Naming Module**
   - Generates standardized resource names following organizational patterns
   - Ensures compliance with Azure naming restrictions
   - Provides consistent outputs for all resource types

2. **Azure Networking Module**
   - Creates virtual network with subnets optimized for Kubernetes workloads
   - Supports availability zone-aware subnet configuration
   - Configures network security groups with appropriate rules

3. **Azure Storage Modules**
   - **Storage Account**: Provides flexible storage account creation with network rules
   - **Storage Container**: Manages blob containers within storage accounts
   - **Storage Roles**: Configures RBAC permissions for storage resources

4. **Azure Key Vault Module**
   - Creates and configures Azure Key Vault with flexible options
   - Supports RBAC authorization model
   - Configurable network rules and security settings

5. **Azure AKS Modules**
   - **AKS Core**: Creates and configures the core Kubernetes cluster
   - **AKS Identity**: Manages service identities for Kubernetes
   - **AKS Node Pools**: Creates and configures node pools for workloads

6. **Azure Container Registry Module**
   - Configures Azure Container Registry for container image storage
   - Supports private networking and RBAC configuration
   - Integrates with AKS for image pull capabilities

7. **Azure Front Door Modules**
   - **Front Door Profile**: Creates the CDN profile for global distribution
   - **Front Door Endpoint**: Configures endpoints for content delivery
   - **Front Door Private Link**: Enables private connectivity to backends

8. **Azure Monitoring Modules**
   - **Log Analytics**: Creates Log Analytics workspace for centralized logging
   - **Monitor Workspace**: Configures Azure Monitor workspace for Prometheus metrics
   - **Prometheus DCR**: Sets up data collection rules for Prometheus metrics
   - **Managed Grafana**: Deploys Azure Managed Grafana for visualization

9. **Azure DNS Module**
   - Configures private DNS zones for internal name resolution
   - Integrates with virtual networks for resolution within VNets
   - Supports private endpoints for Azure PaaS services

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

Environment and region configuration:

```bash
# Work with different environments/regions
make plan ENV=dev REGION=eastus
make plan ENV=ops REGION=westus
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

To run tests for all modules in a specific category:

```bash
make test-category CATEGORY=storage
```

## Documentation

Detailed documentation is available in the `/infra/docs` directory:

- [Documentation Guide](infra/docs/00-documentation-guide.md)
- [Project Introduction](infra/docs/01-introduction.md)
- [Architecture Overview](infra/docs/02-architecture-overview.md)
- [Infrastructure as Code Approach](infra/docs/03-infrastructure-as-code.md)
- [Multi-Cloud Strategy](infra/docs/04-multi-cloud-strategy.md)
- [Environment Management](infra/docs/05-environment-management.md)
- [CIDR Allocation Strategy](infra/docs/06-cidr-allocation.md)
- [Network Topology](infra/docs/07-network-topology.md)
- [Kubernetes Network Design](infra/docs/08-kubernetes-network-design.md)
- [Security Architecture](infra/docs/09-security-architecture.md)
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

# Environment-specific operations
make plan ENV=ops REGION=westus   # Plan ops environment in West US region
make apply ENV=dev REGION=eastus  # Apply dev environment in East US region

# Testing operations
make test                # Run all tests
make test-module         # Test a specific module

# Documentation operations
make docs-check          # Check documentation completeness
make docs-generate       # Generate documentation index
```

For a complete list of commands, run `make help`. 