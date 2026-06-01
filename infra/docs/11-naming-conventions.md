# Reference Platform Naming Conventions

This document outlines the standard naming conventions used across the Reference Platform infrastructure to ensure consistency across all resources and environments.

## General Structure

Most resources follow the CAF-aligned pattern:

```text
{type}-{workload}-{env}-{region_abbv}-{purpose}
```

Where:

- `type` is a short abbreviation for the resource (see table below)
- `workload` is our standard workload identifier (default: "platform")
- `env` is the environment (dev, test, prod)
- `region_abbv` is the shortened region name (e.g., eus, wus)
- `purpose` is optional and describes the specific purpose (e.g., "main", "secondary")

## Environment Abbreviations

| Environment | Abbreviation |
|-------------|--------------|
| Development | dev          |
| Testing     | test         |
| Staging     | staging      |
| Production  | prod         |
| Operations  | ops          |

## Region Abbreviations

### Azure Regions

| Azure Region   | Abbreviation |
|----------------|--------------|
| East US        | eus          |
| West US        | wus          |
| Central US     | cus          |
| North Europe   | neu          |
| West Europe    | weu          |
| Southeast Asia | sea          |
| Australia East | aue          |
| UK South       | uks          |
| Canada Central | cac          |

### AWS Regions

| AWS Region      | Abbreviation |
|-----------------|--------------|
| us-east-1       | use1         |
| us-west-2       | usw2         |
| eu-west-1       | euw1         |
| eu-central-1    | euc1         |
| ap-southeast-1  | apse1        |

### GCP Regions

| GCP Region       | Abbreviation |
|------------------|--------------|
| us-central1      | usc1         |
| us-east1         | use1         |
| europe-west1     | euw1         |
| asia-southeast1  | asse1        |

## Azure Resource Type Abbreviations

| Resource Type                              | Abbreviation | Example                                     |
|--------------------------------------------|--------------|---------------------------------------------|
| Resource Group                             | rg           | rg-platform-dev-eus-net                     |
| Virtual Network                            | vnet         | vnet-platform-dev-eus-main                  |
| Subnet                                     | subnet       | az1-node-subnet                             |
| Network Security Group                     | nsg          | az1-node-subnet-nsg                         |
| Key Vault                                  | kv           | kv-platform-dev-eus-secrets                 |
| Storage Account                            | st           | platformdeveussa001 (special format - see notes) |
| Container Registry                         | acr          | platformdevacr                              |
| AKS Cluster                                | aks          | aks-platform-dev-eus-k8s                    |
| Public IP                                  | pip          | pip-platform-dev-eus-ingress                |
| Load Balancer                              | lb           | lb-platform-dev-eus-app                     |
| Application Gateway                        | agw          | agw-platform-dev-eus-ingress                |
| Private Endpoint                           | pe           | pe-platform-dev-eus-sql                     |
| Private DNS Zone                           | pdns         | privatelink.database.windows.net            |
| Front Door Profile                         | fd           | fd-platform-dev-global                      |
| Front Door Endpoint                        | fd-endpoint  | fd-endpoint-platform-dev-eus-customer       |
| Front Door Origin Group                    | fd-og        | fd-og-platform-dev-eus-customer             |
| Front Door Origin                          | fd-origin    | fd-origin-platform-dev-eus-customer         |
| Front Door Route                           | fd-route     | fd-route-platform-dev-eus-customer          |
| Log Analytics Workspace                    | law          | law-platform-dev-eus-analytics              |
| Monitor Workspace                          | mw           | mw-platform-dev-eus-prometheus              |
| Data Collection Rule                       | dcr          | dcr-platform-dev-eus-prometheus             |
| Data Collection Endpoint                   | dce          | dce-platform-dev-eus-prometheus             |
| Managed Grafana                            | grafana      | grafana-platform-dev-eus-metrics            |
| User-Assigned Managed Identity             | id           | id-platform-dev-eus-aks                     |
| Workload Identity                          | workid       | workid-platform-dev-eus-customer            |
| Federated Credential                       | fedcred      | fedcred-platform-dev-eus-customer           |
| Storage Account Private Endpoint           | pe           | pe-platform-dev-eus-storage                 |
| Storage Container                          | container    | assets, logs, data                          |

## AWS Resource Type Abbreviations

AWS names follow the same `{type}-{workload}-{env}-{region}` pattern. For tight-constraint or globally-unique resources (S3, ECR, ALB, NLB, TG), names are collapsed: `{type}{abbv_workload}{env}{region}`.

| Resource Type              | Abbreviation | Example                                |
|----------------------------|--------------|----------------------------------------|
| VPC                        | vpc          | vpc-platform-dev-use1                  |
| Subnet                     | snet         | snet-platform-dev-use1                 |
| Internet Gateway           | igw          | igw-platform-dev-use1                  |
| NAT Gateway                | natgw        | natgw-platform-dev-use1                |
| Route Table                | rtb          | rtb-platform-dev-use1                  |
| Security Group             | sg           | sg-platform-dev-use1                   |
| EKS Cluster                | eks          | eks-platform-dev-use1                  |
| S3 Bucket                  | s3           | s3platdevuse1 (lowercase, globally unique) |
| ECR Repository             | ecr          | ecrplatdevuse1                         |
| ALB                        | alb          | alb-plat-dev-use1 (32 char max)        |
| NLB                        | nlb          | nlb-plat-dev-use1                      |
| Target Group               | tg           | tg-plat-dev-use1                       |
| Lambda                     | lmb          | lmb-platform-dev-use1                  |
| RDS                        | rds          | rds-platform-dev-use1                  |
| DynamoDB                   | ddb          | ddb-platform-dev-use1                  |
| IAM Role                   | role         | role-platform-dev-use1                 |
| IAM Policy                 | pol          | pol-platform-dev-use1                  |
| KMS Key                    | kms          | kms-platform-dev-use1                  |
| Secrets Manager            | sm           | sm-platform-dev-use1                   |
| EFS                        | efs          | efs-platform-dev-use1                  |

## GCP Resource Type Abbreviations

GCP names follow the same `{type}-{workload}-{env}-{region}` pattern. All GCP resource names must be lowercase. For tight-constraint or globally-unique resources (GCS, service accounts), names are collapsed: `{type}{abbv_workload}{env}{region}`.

| Resource Type              | Abbreviation | Example                                |
|----------------------------|--------------|----------------------------------------|
| VPC Network                | vpc          | vpc-platform-dev-usc1                  |
| Subnet                     | snet         | snet-platform-dev-usc1                 |
| GKE Cluster                | gke          | gke-platform-dev-usc1 (40 char max)    |
| Cloud Storage Bucket       | gcs          | gcsplatdevusc1 (lowercase, globally unique) |
| Artifact Registry          | gcr          | gcrplatdevusc1                         |
| Firewall Rule              | fw           | fw-platform-dev-usc1                   |
| Cloud Router               | rtr          | rtr-platform-dev-usc1                  |
| Cloud NAT                  | nat          | nat-platform-dev-usc1                  |
| Load Balancer              | lb           | lb-platform-dev-usc1                   |
| Cloud SQL                  | sql          | sql-platform-dev-usc1                  |
| Memorystore                | redis        | redis-platform-dev-usc1                |
| Pub/Sub Topic              | pst          | pst-platform-dev-usc1                  |
| KMS Key Ring               | kr           | kr-platform-dev-usc1                   |
| Service Account            | sa           | sa-plat-dev-usc1 (30 char max)         |
| Cloud Run                  | run          | run-platform-dev-usc1                  |
| Compute Engine             | gce          | gce-platform-dev-usc1                  |
| Cloud Function             | gcf          | gcf-platform-dev-usc1                  |

## Specific Resource Conventions

### Availability Zone Resources

For resources distributed across availability zones, prepend the AZ number:

```text
az{number}-{resource_type}-{purpose}
```

Examples:

- `az1-node-subnet` (Subnet for nodes in AZ1)
- `az2-lb-subnet` (Subnet for load balancers in AZ2)
- `az3-endpoint-subnet` (Subnet for private endpoints in AZ3)

### Storage Accounts

Storage accounts have a 24 character limit and cannot use hyphens. They follow this pattern:

```text
{workload}{env}{region_abbv}st{instance}
```

Example: `platformdeveusstdata001`

### Container Names

Container names in Storage Accounts are consistent across all deployments:

- assets
- logs
- data
- backups
- archives

### Customer-Specific Resources

For customer-specific resources:

```text
{type}-{workload}-{env}-{region_abbv}-{customer}
```

Example: `kv-platform-dev-eus-customer1`

### Role Assignments

Role assignments for RBAC use a descriptive approach:

```text
{resource}-{role}-{principal-type}
```

Examples:

- `storage-contributor-developers`
- `keyvault-reader-app`
- `aks-admin-operations`

### Private Link Resources

Private link resources follow:

```text
pe-{workload}-{env}-{region_abbv}-{service}
```

Example: `pe-platform-dev-eus-keyvault`

### Deployment ID

The `deployment_id` is a special identifier used for customer applications:

- Format: Often (but not always) follows a pattern of customer name and environment

  ```text
  {customer}-{env}
  ```

- Examples:
  - `mycustomer-dev`
  - `my-customer-dev`
  - `legacy-app-01` (example of pre-existing naming that doesn't follow the standard pattern)

- Usage:
  - Primarily used for Kubernetes namespace naming in workload identity federation
  - Serves as an identifier for customer-specific applications
  - Distinct from the core infrastructure naming conventions

- Important Note:
  - Pre-existing applications may have deployment IDs that don't conform to the standard pattern
  - Always verify the correct deployment_id rather than assuming the {customer}-{env} format
  - When creating new deployment IDs, prefer the standard format unless there's a specific reason to deviate

## Tagging Conventions

All resources should include the following standard tags:

| Tag Name           | Description                                       | Example                            |
|--------------------|---------------------------------------------------|------------------------------------|
| Environment        | Deployment environment                            | "dev", "test", "prod"              |
| ManagedBy          | Tool managing the resource                        | "Terragrunt"                       |
| Component          | System component                                  | "Networking", "Compute", "Storage" |
| Project            | Project name                                      | "Multi-Cloud Platform"             |
| DataClassification | Data sensitivity                                  | "Internal", "Confidential"         |
| Region             | Azure region                                      | "eastus", "westus"                 |
| AutoShutdown       | Auto-shutdown eligibility                         | "True", "False"                    |
| CIDRHierarchy      | For network resources, position in CIDR hierarchy | "Azure-Dev-EastUS"                 |
| NetworkDesign      | Network design pattern                            | "Kubernetes3AZ"                    |
| CreatedDate        | Date when the resource was created                | "2023-06-01"                       |

## Variable Naming Conventions

All Terraform modules follow these standard variable naming conventions:

### Resource Toggle: `create`

Every resource-creating module includes a `variable "create"` (type `bool`, default `true`) that controls whether the module provisions any resources. This is the standard toggle name across all 19 resource-creating modules.

- Resources use `count = var.create ? 1 : 0` or `for_each = var.create ? ... : {}`.
- Outputs return `null` (for scalars) or `{}` (for maps) when `create = false`.

```hcl
variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}
```

### Optional String Defaults: `null`

Optional string variables default to `null`, not `""`. This allows clean conditional logic with `!= null` checks and avoids ambiguity between "not set" and "set to empty string".

```hcl
variable "name" {
  description = "The name of the resource (generated if not provided)"
  type        = string
  default     = null
}
```

### Sub-Feature Flags: `enable_*`

Boolean variables that control optional sub-features within a module use the `enable_` prefix. These are distinct from the top-level `create` toggle.

```hcl
variable "enable_eks_networking" {
  description = "Whether to create EKS-specific networking resources"
  type        = bool
  default     = false
}

variable "enable_cloud_nat" {
  description = "Whether to create a Cloud NAT gateway"
  type        = bool
  default     = true
}
```

## Implementation in Terraform

### Basic Naming Convention

Use locals to construct resource names consistently:

```hcl
locals {
  workload      = "platform"
  environment   = "dev"
  region        = "eastus"
  region_abbv   = "eus"
  component     = "net"
  
  # Resource Group
  resource_group_name = "rg-${local.workload}-${local.environment}-${local.region_abbv}-${local.component}"
  
  # Virtual Network
  vnet_name = "vnet-${local.workload}-${local.environment}-${local.region_abbv}-main"
  
  # Storage Account (no hyphens, 24 char limit)
  storage_account_name = "${local.workload}${local.environment}${local.region_abbv}st001"
}
```

### Terragrunt Implementation with Naming Module

The Reference Platform uses a centralized naming approach with Terragrunt to manage dependencies between the naming module and resource modules. All three cloud naming modules (`azure/naming`, `aws/naming`, `gcp/naming`) share the same input contract -- `workload`, `environment`, `region_abbv` -- so Terragrunt live configs can pass the same locals regardless of cloud provider.

1. **Dedicated Naming Module**: A specialized module that generates standardized resource names based on inputs.

2. **Terragrunt Dependency Management**: Terragrunt manages dependencies between modules, passing naming outputs to resource modules.

```hcl
# Example naming module configuration in Terragrunt
# File: infra/live/azure/dev/eastus/naming/terragrunt.hcl
terraform {
  source = "${get_repo_root()}/infra/modules/azure//naming"
}

inputs = {
  workload    = local.workload
  environment = local.env
  region_abbv = local.region_abbv
}
```

Resource modules don't use the naming module internally, but rather receive naming values through Terragrunt's dependency mechanism:

```hcl
# Example resource group configuration in Terragrunt
# File: infra/live/azure/dev/eastus/resource_group/terragrunt.hcl

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group_name = "mock-rg"
  }
}

# Specify inputs specific to this module
inputs = {
  # Resource configuration
  name     = dependency.naming.outputs.resource_group_name
  location = local.region
  
  # Tags and other inputs
  tags = local.tags
}
```

This approach provides several advantages:

1. **Centralized Naming Conventions**: All resource names are generated from a single source of truth.
2. **Separation of Concerns**: Resources modules focus on resource configuration, not naming logic.
3. **Consistent Implementation**: The same naming patterns are applied across all environments.
4. **Flexible Updates**: Naming conventions can be updated centrally without modifying resource modules.

All infrastructure follows this pattern through Terragrunt's dependency management features.

## Reference

For CIDR allocation strategy details, see [CIDR Allocation Strategy](06-cidr-allocation.md).

For security naming considerations, see [Security Architecture](09-security-architecture.md).

For multi-cloud naming strategies, see [Multi-Cloud Strategy](04-multi-cloud-strategy.md).
