# Terraform Modules

This directory contains reusable Terraform modules for infrastructure deployment across multiple cloud providers. These modules are designed to be composable building blocks that can be used by Terragrunt configurations in the `/infra/live` directory.

## Module Organization

Modules are organized by cloud provider:

```
modules/
├── aws/        # AWS-specific modules
├── azure/      # Azure-specific modules
├── gcp/        # Google Cloud Platform modules
└── common/     # Provider-agnostic modules
```

## Azure Modules

| Module | Description |
|--------|-------------|
| [aks](azure/aks) | Creates a production-ready AKS cluster with multiple node pools |
| [networking](azure/networking) | Provisions Azure networking components including VNets, subnets, and NSGs |
| [container_registry](azure/container_registry) | Deploys Azure Container Registry with network and security controls |
| [key_vault](azure/key_vault) | Provisions Key Vault with proper security and network isolation |
| [storage](azure/storage) | Creates Azure Storage accounts and containers with proper security controls |
| [monitoring](azure/monitoring) | Sets up Azure Monitor and Log Analytics for infrastructure monitoring |
| [resource_group](azure/resource_group) | Creates resource groups with standardized tagging |
| [naming](azure/naming) | Standardizes resource naming across deployments |

## AWS Modules

| Module | Description |
|--------|-------------|
| [eks](aws/eks) | Creates a production-ready Amazon EKS cluster |
| [vpc](aws/vpc) | Provisions VPC, subnets, routing tables, and security groups |
| [ecr](aws/ecr) | Deploys Elastic Container Registry with proper permissions |
| [s3](aws/s3) | Creates S3 buckets with appropriate security and lifecycle policies |
| [rds](aws/rds) | Sets up managed databases with security and networking controls |
| [iam](aws/iam) | Manages IAM policies, roles, and service accounts |
| [kms](aws/kms) | Manages encryption keys for various AWS services |

## GCP Modules

| Module | Description |
|--------|-------------|
| [gke](gcp/gke) | Creates Google Kubernetes Engine clusters |
| [network](gcp/network) | Provisions VPC network, subnets, and firewall rules |
| [gcr](gcp/gcr) | Sets up Google Container Registry |
| [gcs](gcp/gcs) | Creates Cloud Storage buckets with proper security |
| [gcp_iam](gcp/iam) | Manages IAM policies and service accounts |
| [cloud_sql](gcp/cloud_sql) | Provisions Cloud SQL instances with networking and security |

## Common Modules

| Module | Description |
|--------|-------------|
| [kubernetes](common/kubernetes) | Provider-agnostic Kubernetes configurations |
| [observability](common/observability) | Multi-cloud monitoring and logging solutions |
| [dns](common/dns) | Manages DNS configurations across cloud providers |

## Module Design Principles

All modules adhere to the following design principles:

1. **Consistency**: Modules follow consistent patterns for variable naming, outputs, and structure.
2. **Composability**: Modules can be combined and integrated with each other.
3. **Security by Default**: Secure configurations are the default.
4. **Testability**: Modules include automated tests.
5. **Documentation**: Each module includes comprehensive README files.
6. **Maintainability**: Modules are designed for long-term maintenance.

## Module Usage

Each module includes a detailed README.md file with descriptions, required inputs, outputs, and usage examples. See the specific module directories for detailed documentation.

Example of using a module with Terragrunt:

```hcl
# terragrunt.hcl
terraform {
  source = "../../modules/azure/networking"
}

inputs = {
  resource_group_name = "example-rg"
  location            = "eastus"
  name                = "example-vnet"
  address_space       = ["10.0.0.0/16"]
  
  subnets = {
    "subnet1" = {
      address_prefix = "10.0.1.0/24"
      security_rules = []
    }
  }
}
```

## Versioning and Updating

Modules are versioned using git tags. When updating modules:

1. Test changes thoroughly
2. Update module documentation
3. Increment version numbers according to semantic versioning
4. Create a new release tag

## Contributing

When contributing to modules:

1. Follow the established patterns and naming conventions
2. Include comprehensive documentation
3. Write and update tests for the module
4. Include usage examples
5. Update the main README.md if adding a new module 