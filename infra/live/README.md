# Terragrunt Environments

This directory contains all the environment-specific Terragrunt configurations that compose our infrastructure using the reusable modules from the `/infra/modules` directory.

## Directory Structure

The infrastructure is organized in a hierarchical structure following Terragrunt best practices:

```
live/
├── _envcommon/            # Common configuration for environments
├── common.hcl             # Common variables for all environments
├── aws/                   # AWS-specific configurations
│   ├── common.hcl         # Common variables for AWS
│   ├── dev/               # Development environment
│   │   ├── account.hcl    # AWS account-specific variables
│   │   ├── region.hcl     # Region-specific variables
│   │   ├── us-east-1/     # Region-specific resources
│   │   │   ├── vpc/
│   │   │   ├── eks/
│   │   │   └── ...
│   ├── staging/
│   └── prod/
├── azure/                 # Azure-specific configurations
│   ├── common.hcl         # Common variables for Azure
│   ├── dev/               # Development environment
│   │   ├── subscription.hcl  # Azure subscription variables
│   │   ├── eastus/       # Region-specific resources
│   │   │   ├── resource_group/
│   │   │   ├── networking/
│   │   │   ├── aks_core/
│   │   │   ├── aks_node_pools/
│   │   │   └── ...
│   ├── staging/
│   └── prod/
└── gcp/                   # GCP-specific configurations
    ├── common.hcl         # Common variables for GCP
    ├── dev/
    ├── staging/
    └── prod/
```

## Environment Overview

### Development (dev)
- Purpose: Development and testing environment
- Characteristics:
  - Lower-cost infrastructure
  - More permissive network access
  - Quick provisioning and teardown
  - Used for feature development and testing

### Staging
- Purpose: Pre-production validation environment
- Characteristics:
  - Production-like configuration
  - Similar to production scale but potentially smaller
  - Used for release candidate testing
  - Validates infrastructure changes before production

### Production (prod)
- Purpose: Live customer-facing environment
- Characteristics:
  - High availability configuration
  - Multiple availability zones
  - Strict security controls
  - Formal change management process

## Multi-Cloud Strategy

Our infrastructure implements a multi-cloud strategy with components deployed across:

1. **Azure**: Primary platform for container orchestration (AKS) and related services
2. **AWS**: Used for specific services like data analytics and global content delivery
3. **GCP**: Leveraged for machine learning workloads and specialized services

Each cloud environment follows similar patterns but is adapted to the specific provider's services and best practices.

## Getting Started

### Prerequisites
- Terragrunt v0.45.0 or newer
- Terraform v1.6.0 or newer
- Valid cloud provider credentials configured

### Common Commands

#### Applying Infrastructure Changes

To apply changes to a specific component:

```bash
# Navigate to the component directory
cd infra/live/azure/dev/eastus/networking

# Initialize and apply
terragrunt init
terragrunt plan
terragrunt apply
```

To apply changes to all components in an environment:

```bash
# Navigate to the environment directory
cd infra/live/azure/dev/eastus

# Apply all (with auto-approval)
terragrunt run-all apply
```

#### Destroying Infrastructure

To destroy a specific component:

```bash
cd infra/live/azure/dev/eastus/networking
terragrunt destroy
```

To destroy all components in an environment:

```bash
cd infra/live/azure/dev/eastus
terragrunt run-all destroy
```

## Dependency Management

Terragrunt automatically manages dependencies between components based on the `dependency` blocks in each `terragrunt.hcl` file. The general dependency flow is:

1. Core networking (VPC/VNet)
2. Security services (IAM/Key Vault)
3. Data services (Storage/Databases)
4. Compute services (EC2/VMs/AKS)
5. Application services

## CI/CD Integration

This infrastructure is designed to be deployed through CI/CD pipelines:

1. **Pull Request Validation**: 
   - `terragrunt run-all plan` to validate changes

2. **Deployment**:
   - Development: Automatic on merge to main branch
   - Staging: Automatic with approval
   - Production: Manual approval required

## State Management

Terraform state is stored remotely:
- Azure environments: Azure Storage Account
- AWS environments: S3 + DynamoDB
- GCP environments: GCS bucket

Each component has its own state file to minimize blast radius of changes.

## Best Practices

1. **Never modify state manually**: Use Terragrunt commands to manage state.
2. **Use workspaces judiciously**: Prefer directory structure over workspaces.
3. **Keep modules DRY**: Use common variables and shared modules.
4. **Document all changes**: Keep README files updated with latest configurations.
5. **Lock provider versions**: Specify exact provider versions in `.tf` files.
6. **Test changes first**: Always test changes in dev before promoting to higher environments.

## Troubleshooting

Common issues:

1. **State locking timeout**: Another process may be running Terragrunt.
   - Check for running processes or manually release the lock.

2. **Provider authentication failure**:
   - Verify cloud credentials are properly configured.

3. **Dependency resolution errors**:
   - Ensure all referenced components exist and outputs are correctly defined.

For additional help, consult the documentation or reach out to the infrastructure team. 

## Remote State Configuration

This project uses a centralized Azure Storage for Terraform state management across all environments, regions, and subscriptions. All Terraform state is stored in the Innovation-Operations subscription with the following configuration:

- **Subscription**: Innovation-Operations (9dc5edc4-8c4e-41a1-a4f8-2183c4e91954)
- **Resource Group**: `terraform-state-rg`
- **Storage Account**: `tfstatemulticloud` (fixed name in the Innovation-Operations subscription)
- **Container**: A single container named `terraformstate` for all environments
- **Key**: The full path that reflects the directory structure (e.g., `azure/dev/eastus/networking/terraform.tfstate`)

This centralized approach offers several benefits:
- Single subscription for all state management, simplifying access control
- Subscription-independent state storage that survives subscription changes
- Centralized monitoring, backup, and management of all state files
- Consistent state locking across all infrastructure components
- Simplified disaster recovery planning

### Setting Up Remote State

A setup script is provided to create the required Azure resources and optionally migrate existing state:

```bash
# Ensure you're logged in to Azure
az login

# For basic setup
./infra/scripts/setup-remote-state.sh

# Specify a different location
./infra/scripts/setup-remote-state.sh -l westus2

# To also migrate existing local state files
./infra/scripts/setup-remote-state.sh -m

# For help and available options
./infra/scripts/setup-remote-state.sh -h
```

The script automatically:
1. Sets the Azure CLI context to the Innovation-Operations subscription
2. Creates the resource group, storage account, and container if they don't exist
3. Configures diagnostic settings with a Log Analytics workspace
4. Assigns appropriate RBAC permissions for Terraform state access
5. Optionally migrates existing state files

### Manual State Migration

If you prefer to migrate state files manually:

1. First run the setup script to create the Azure resources
2. Navigate to the component directory
3. Run `terragrunt init -reconfigure` and answer "yes" when prompted to migrate state

### Security Considerations

- The storage account is configured with private access only
- HTTPS is enforced
- TLS 1.2+ is required
- Diagnostic settings are configured with a Log Analytics workspace
- Azure AD authentication is enabled for state access 