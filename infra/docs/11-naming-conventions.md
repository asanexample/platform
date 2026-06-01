# Reference Platform Naming Conventions

This document outlines the standard naming conventions used across the Reference Platform infrastructure to ensure consistency across all resources and environments.

> **AWS-first:** AWS is the only deployed cloud — the **AWS Resource Type Abbreviations** table below is the live one. The Azure/GCP region and resource tables are kept as **reference** for when those clouds land (multi-cloud by design); they are not in use today. There is **no naming module** — names are composed inline from `workload`/`env`/`region_abbv` locals surfaced by `_base.hcl`.

## General Structure

Most resources follow the CAF-aligned pattern:

```text
{type}-{workload}-{env}-{region_abbv}-{purpose}
```

Where:

- `type` is a short abbreviation for the resource (see table below)
- `workload` is our standard workload identifier (default: "platform")
- `env` is the environment (dev, test, prod)
- `region_abbv` is the shortened region name (e.g., use1, usw2)
- `purpose` is optional and describes the specific purpose (e.g., "main", "secondary")

## Environment Abbreviations

The deployed AWS environments (one account each). `dev`/`staging` remain reserved generic
abbreviations for future use.

| Environment | Abbreviation | Deployed |
|-------------|--------------|----------|
| Management  | mgmt         | Yes (Organizations, Identity Center, state) |
| Platform    | platform     | Yes (hub cluster + shared services) |
| Test        | test         | Yes (Terratest CI sandbox) |
| Preprod     | preprod      | Yes (full tenant cluster) |
| Production  | prod         | Yes (networking + org scaffolding) |
| Development | dev          | Reserved |
| Staging     | staging      | Reserved |

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

## Azure Resource Type Abbreviations (reference — planned cloud, not deployed)

> Azure is not deployed today. This table is the reserved convention for when Azure lands; the **AWS** table below is the live one.

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

## GCP Resource Type Abbreviations (reference — planned cloud, not deployed)

> GCP is not deployed today. This table is the reserved convention for when GCP lands.

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

> The subsections below (Storage Accounts, Container Names, Customer-Specific, Role Assignments,
> Private Link, Deployment ID) describe **Azure** constructs and are **reference for the planned Azure
> cloud** — not in use today. The AWS equivalents in production are S3 buckets (see the AWS table above),
> Secrets Manager, VPC endpoints / PrivateLink, and per-team `team-<team>/<app>` namespaces.

### Storage Accounts (Azure reference)

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
| Project            | Project name                                      | "Reference Platform"               |
| DataClassification | Data sensitivity                                  | "Internal", "Confidential"         |
| Region             | AWS region                                        | "us-east-1", "us-west-2"           |
| AutoShutdown       | Auto-shutdown eligibility                         | "True", "False"                    |
| CIDRHierarchy      | For network resources, position in CIDR hierarchy | "AWS-Platform-UsEast1"             |
| NetworkDesign      | Network design pattern                            | "Kubernetes3AZ"                    |
| CreatedDate        | Date when the resource was created                | "2023-06-01"                       |

## Variable Naming Conventions

All Terraform modules follow these standard variable naming conventions:

### Resource Toggle: `create`

Every resource-creating module includes a `variable "create"` (type `bool`, default `true`) that controls whether the module provisions any resources. This is the standard toggle name across all resource-creating modules.

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

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs"
  type        = bool
  default     = true
}
```

## Implementation in Terraform

### Basic Naming Convention

Use locals to construct resource names consistently:

```hcl
locals {
  workload    = "platform"
  region_abbv = "use1"

  # VPC
  vpc_name = "vpc-${local.workload}-${local.region_abbv}"

  # EKS cluster
  cluster_name = "eks-${local.workload}-${local.region_abbv}"

  # S3 bucket (no hyphens needed, lowercase, globally unique — collapse + org prefix)
  bucket_name = "${var.org_name}-${local.workload}-${local.region_abbv}-data"
}
```

### How names are composed (no naming module)

There is **no dedicated naming module** today. The composition dimensions (`workload`,
`environment`, `region_abbv`) are surfaced by `_base.hcl` to every unit via
`include.base.locals.*`, and unit/module locals compose the name inline:

```hcl
# In a unit's terragrunt.hcl / a module's main.tf
locals {
  name = "${include.base.locals.workload}-${include.base.locals.env}-${include.base.locals.region_abbv}"
}

inputs = {
  cluster_name = "eks-${include.base.locals.workload}-${include.base.locals.region_abbv}" # e.g. eks-platform-use1
  vpc_name     = "vpc-${include.base.locals.workload}-${include.base.locals.region_abbv}"
}
```

This keeps the naming dimensions centralized (in `_base.hcl`) while avoiding an extra module +
dependency in the DAG. If naming complexity grows, a shared naming module with the same
`workload`/`environment`/`region_abbv` contract could be added without changing callers materially.

## Reference

For CIDR allocation strategy details, see [CIDR Allocation Strategy](06-cidr-allocation.md).

For security naming considerations, see [Security Architecture](09-security-architecture.md).

For multi-cloud naming strategies, see [Multi-Cloud Strategy](04-multi-cloud-strategy.md).
