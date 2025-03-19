# Multi-Cloud Infrastructure as Code

This repository contains Infrastructure as Code (IaC) for managing resources across multiple cloud providers (AWS, Azure, GCP) using Terraform with Terragrunt.

## Repository Structure

```
infra/
├── _envcommon/              # Common configurations for environments
├── modules/                 # Reusable modules
│   ├── aws/                 # AWS-specific modules
│   ├── azure/               # Azure-specific modules
│   ├── gcp/                 # GCP-specific modules
│   └── common/              # Cross-cloud abstraction modules
└── live/                    # Live infrastructure
    ├── global/              # Global resources
    └── aws/azure/gcp        # Per-cloud resources
        └── env/region/      # Environment & region-specific
```

## Getting Started

### Prerequisites

- Terraform >= 1.6.0
- Terragrunt >= 0.45.0
- Azure CLI (for Azure resources)
- AWS CLI (for AWS resources)
- Google Cloud SDK (for GCP resources)

### Environment Setup

Set the required environment variables:

```bash
# Common
export TF_VAR_environment="dev"
export TF_VAR_cost_center="Engineering"
export TF_VAR_owner="Platform Team"

# Azure
export TF_VAR_azure_subscription_id="your-subscription-id"
export TF_VAR_azure_tenant_id="your-tenant-id"
export TF_VAR_azure_region="eastus"

# AWS (when needed)
export TF_VAR_aws_region="us-east-1"

# GCP (when needed)
export TF_VAR_gcp_project_id="your-project-id"
export TF_VAR_gcp_region="us-east1"
```

### Deployment

To deploy a specific component:

```bash
cd infra/live/azure/dev/eastus/networking
terragrunt plan
terragrunt apply
```

To deploy all components in an environment:

```bash
cd infra/live/azure/dev
terragrunt run-all plan
terragrunt run-all apply
```

## Testing

This repository uses Terraform's native testing framework for validating modules:

```bash
# Run all tests
make test

# Test a specific module
make test-module MODULE=networking
```

The testing targets in the Makefile run tests for all Azure modules and provide a summary of results. Tests are designed to validate module configurations without creating actual resources.

## Available Modules

The following reusable modules are available:

### Azure Modules

- **Networking**: Virtual network, subnets, NSGs, and related networking resources
- **Storage Account**: Azure Storage Accounts with configurable settings
- **Storage Container**: Blob containers with access control and metadata
- **Key Vault**: Azure Key Vault with RBAC/access policies, network rules, and private endpoints
- **Hosting**: Combined networking, storage, and key vault setup for complete application hosting
- **Naming**: Standardized resource naming following Azure best practices
- **Terraform State**: Backend storage for Terraform state files

## Naming Conventions

Resources follow standardized naming patterns using the Azure naming module. This ensures consistency across all resources and compliance with Azure's naming restrictions.

### General Pattern
For most resources: `{prefix}-{customer}-{stage}-{resource_type}-{region_abbv}`

For shared resources (no customer): `{prefix}-{stage}-{resource_type}-{region_abbv}`

Examples:
- `vip-contoso-dev-rg-eus` (Customer-specific Azure resource group)
- `vip-prod-vnet-wus` (Shared Azure virtual network)
- `vipcontosodevsaeus` (Storage account with special formatting)

See the [NAMING_CONVENTIONS.md](docs/NAMING_CONVENTIONS.md) document for detailed naming rules and patterns.

### Using the Naming Module

All infrastructure modules now use the naming module internally, which enforces standardized naming:

```hcl
module "hosting" {
  source = "../../modules/azure/hosting"
  
  # Naming parameters
  prefix      = "vip"
  customer    = "contoso"  # Optional
  stage       = "dev"
  region_abbv = "eus"
  
  # Other parameters...
}
```

## Tagging Strategy

All resources are tagged with:
- Environment
- ManagedBy
- Project
- CostCenter
- Owner

Environment-specific resources may have additional tags.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 