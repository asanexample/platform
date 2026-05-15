# Multi-Cloud Platform Infrastructure

This repository contains infrastructure-as-code for a multi-cloud platform using OpenTofu and Terragrunt, spanning AWS, Azure, and GCP. It emphasizes security, reusability, and consistent implementation patterns across all three clouds.

## Project Structure

```
platform/
├── infra/                       # Infrastructure code
│   ├── docs/                    # Operational documentation (20+ docs)
│   │   ├── 00-documentation-guide.md
│   │   ├── 01-introduction.md
│   │   ├── 02-architecture-overview.md
│   │   ├── ...
│   │   ├── 20-region-scaffolding.md
│   │   └── README.md
│   ├── live/                    # Live infrastructure (Terragrunt)
│   │   ├── aws/
│   │   │   ├── _base.hcl        # AWS base config
│   │   │   ├── _versions.hcl    # Module sources and version pins
│   │   │   ├── mgmt/global/     # Management account
│   │   │   │   ├── organizations/   # AWS Organizations + SCPs
│   │   │   │   └── state-bootstrap/ # S3 + DynamoDB remote state
│   │   │   └── ops/us-east-1/   # Operations (networking + naming)
│   │   ├── azure/
│   │   │   ├── _base.hcl        # Azure base config
│   │   │   ├── _versions.hcl    # Module sources and Helm version pins
│   │   │   ├── _envcommon/      # Shared configs across environments
│   │   │   ├── dev/eastus/      # Development (full stack)
│   │   │   └── ops/westus/      # Operations (full stack)
│   │   └── gcp/
│   │       ├── _base.hcl        # GCP base config
│   │       └── ops/us-east1/    # Operations (networking + naming)
│   ├── modules/                 # Reusable modules
│   │   ├── aws/                 # 4 modules: naming, networking, organizations, state_bootstrap
│   │   ├── azure/               # 24 modules (see below)
│   │   ├── gcp/                 # 2 modules: naming, networking
│   │   ├── argocd/              # GitOps deployment via Helm
│   │   ├── argocd-bootstrap/    # Bootstrap applications
│   │   ├── cilium/              # CNI deployment via Helm
│   │   ├── policy/              # OPA/Gatekeeper policy engine
│   │   └── vcluster/            # Virtual Kubernetes clusters
│   ├── terragrunt.hcl           # Root Terragrunt configuration
│   └── tests/                   # Test configurations
│       ├── helpers/
│       ├── modules/azure/
│       └── setup/
├── docs/                        # AWS Organizations & compliance docs
│   ├── adrs/                    # 6 architecture decision records
│   ├── architecture/            # Config hierarchy, AWS Org design
│   ├── compliance/              # SOC2/HIPAA/PCI-DSS/NIST/CIS mapping
│   ├── runbooks/                # Operational runbooks
│   ├── troubleshooting/         # Troubleshooting guides
│   ├── onboarding.md
│   └── user-guide.md
├── Makefile                     # Infrastructure operations automation
├── scripts/                     # Utility scripts
├── charts/                      # Helm charts
└── terragrunt.hcl               # Root Terragrunt config (cloud-aware state routing)
```

## Features

- **Multi-Cloud Architecture**: AWS, Azure, and GCP with cross-cloud interface contract (`network_id`, `subnet_ids`, `kubernetes_subnet_id`) for cloud-agnostic downstream modules
- **AWS Organizations**: Full org management with OUs (Platform, Workloads/Preprod, Workloads/Prod, Workloads/Regulated), multiple accounts, and 8 enterprise SCPs
- **Enterprise Security Controls**: SCPs enforcing encryption, region restrictions, IMDSv2, root user protection, security service protection (CloudTrail, GuardDuty, Security Hub, Config, Access Analyzer), tagging requirements, and HIPAA-eligible service restrictions
- **Cloud-Aware State Management**: S3 backend for AWS (mgmt account 851725353202), Azure Blob Storage for Azure — root `terragrunt.hcl` detects cloud from directory path and routes automatically
- **7-Layer Config Hierarchy**: Root `terragrunt.hcl` > cloud `_base.hcl` > `_versions.hcl` > env `common.hcl` > region > workload > module
- **Environment Safety Validations**: Automatic path-env consistency checks and subscription/account mapping verification prevent cross-environment deployment accidents
- **Hierarchical CIDR Allocation**: Well-structured address space across all clouds (see [CIDR Allocation Strategy](infra/docs/06-cidr-allocation.md))
- **Universal Create Toggles**: Every resource-creating module supports `create = true/false` for selective deployment without config removal
- **Composite Module Pattern**: Stack modules (e.g., `stack_base`) compose multiple modules into single deployable units
- **AKS Cluster Support**: Kubernetes clusters with Cilium CNI, node pools, workload identity, and ArgoCD GitOps
- **Monitoring & Observability**: Log Analytics, Prometheus, Managed Grafana, diagnostic settings, and monitor alerts
- **Front Door Integration**: Global content delivery and security with Azure Front Door, private link backends
- **Standardized Naming**: Consistent resource naming across all clouds via dedicated naming modules
- **Compliance Documentation**: Mapping to SOC2, HIPAA, PCI-DSS, NIST, and CIS frameworks

## Modules

### AWS (4 modules)

| Module | Description |
|--------|-------------|
| `naming` | Resource naming conventions |
| `networking` | VPC, subnets, Internet Gateway, NAT Gateway, route tables |
| `organizations` | AWS Organizations, OUs, accounts, 8 enterprise SCPs (baseline-guardrails, protect-security-services, enforce-encryption, deny-regions, protect-data-and-network, require-tagging, restrict-iam-users, hipaa-eligible-services) |
| `state_bootstrap` | S3 bucket + DynamoDB table for Terraform remote state |

### Azure (24 modules)

| Module | Description |
|--------|-------------|
| `aks_core` | AKS cluster core configuration |
| `aks_identity` | AKS managed identities |
| `aks_node_pools` | AKS node pool management |
| `client_config` | Azure client configuration data |
| `container_registry` | Azure Container Registry with private networking |
| `diagnostic_settings` | Azure Monitor diagnostic settings |
| `frontdoor_endpoint` | Front Door endpoint configuration |
| `frontdoor_private_link` | Front Door private link connectivity |
| `frontdoor_profile` | Front Door CDN profile |
| `identities` | Azure managed identities |
| `key_vault` | Azure Key Vault with RBAC authorization |
| `log_analytics` | Log Analytics workspace |
| `managed_grafana` | Azure Managed Grafana |
| `monitor_alerts` | Azure Monitor alert rules |
| `monitor_workspace` | Azure Monitor workspace for Prometheus |
| `naming` | Resource naming conventions |
| `networking` | Virtual network, subnets, NSGs |
| `private_dns` | Private DNS zones |
| `prometheus_dcr` | Prometheus data collection rules |
| `resource_group` | Resource group management |
| `stack_base` | Composite: resource_group + networking + key_vault |
| `storage_account` | Storage account with network rules |
| `storage_container` | Blob container management |
| `storage_roles` | Storage RBAC permissions |

### GCP (2 modules)

| Module | Description |
|--------|-------------|
| `naming` | Resource naming conventions |
| `networking` | VPC, subnets, Cloud Router, Cloud NAT |

### Cross-Cloud (5 modules)

| Module | Description |
|--------|-------------|
| `cilium` | CNI deployment via Helm (works with AKS, EKS, GKE) |
| `argocd` | GitOps deployment via Helm |
| `argocd-bootstrap` | Bootstrap applications (cert-manager, external-dns, external-secrets) |
| `policy` | OPA/Gatekeeper policy engine |
| `vcluster` | Virtual Kubernetes clusters |

## Live Environments

| Path | Cloud | Purpose |
|------|-------|---------|
| `aws/mgmt/global/` | AWS | Management account: state-bootstrap + organizations |
| `aws/ops/us-east-1/` | AWS | Operations: networking + naming |
| `azure/dev/eastus/` | Azure | Development: full stack (AKS, monitoring, Front Door, DNS, storage, etc.) |
| `azure/ops/westus/` | Azure | Operations: full stack + ArgoCD |
| `azure/_envcommon/` | Azure | Shared configurations across environments |
| `gcp/ops/us-east1/` | GCP | Operations: networking + naming |

## AWS Organizations

- **Organization**: `o-a4kjvito7o`, management account `851725353202`
- **Accounts**: platform (`829808296602`), preprod (`620830101009`)
- **OU structure**: Platform, Workloads/{Preprod, Prod, Regulated}
- **SCPs**: 7 default + 1 optional HIPAA SCP, covering root user lockdown, region restrictions, encryption enforcement, security service protection, tagging requirements, and IAM user restrictions

## Getting Started

### Prerequisites

- OpenTofu >= 1.6.0
- Terragrunt >= 0.55.0
- AWS CLI (for AWS environments)
- Azure CLI (for Azure environments)
- Google Cloud SDK (for GCP environments)

### Authentication

```bash
# AWS
aws configure
# or use SSO
aws sso login --profile your-profile

# Azure
az login
az account set --subscription "your-subscription-id"

# GCP
gcloud auth application-default login
gcloud config set project your-project-id
```

### Deployment

The project includes a Makefile to simplify operations:

```bash
# Show available commands
make help

# Plan all modules in an environment
make plan CLOUD=azure ENV=dev REGION=eastus

# Apply all modules in an environment
make apply CLOUD=azure ENV=ops REGION=westus

# Work with a specific module
make plan-module MODULE=networking CLOUD=azure ENV=dev REGION=eastus
make apply-module MODULE=aks_core CLOUD=azure ENV=ops REGION=westus

# Work with AWS
make plan CLOUD=aws ENV=mgmt REGION=global
make plan CLOUD=aws ENV=ops REGION=us-east-1

# Validate OpenTofu code
make validate

# Check tool versions
make version

# Clean Terragrunt cache
make clean
```

## Testing

Module tests are organized in `infra/tests/modules/`, separate from module code:

```bash
# Run all tests
make test

# Run tests for a specific module
make test-module MODULE=networking
```

## Documentation

### Operational Docs (`infra/docs/`)

20+ documents covering architecture, security, networking, and operations:

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
- [Compliance Framework](infra/docs/10-compliance-framework.md)
- [Naming Conventions](infra/docs/11-naming-conventions.md)
- [Tagging Strategy](infra/docs/12-tagging-strategy.md)
- [Module Design](infra/docs/13-module-design.md)
- [Deployment Workflows](infra/docs/14-deployment-workflows.md)
- [Testing Strategy](infra/docs/15-testing-strategy.md)
- [Disaster Recovery](infra/docs/16-disaster-recovery.md)
- [Available Modules](infra/docs/17-available-modules.md)
- [Troubleshooting](infra/docs/18-troubleshooting.md)
- [Cost Management](infra/docs/19-cost-management.md)
- [Region Scaffolding](infra/docs/20-region-scaffolding.md)

Full index: [Documentation Table of Contents](infra/docs/README.md)

### AWS Organizations & Compliance Docs (`docs/`)

- **ADRs**: [Multi-cloud structure](docs/adrs/001-multi-cloud-terragrunt-structure.md), [AWS state storage](docs/adrs/002-aws-state-storage.md), [SCP design](docs/adrs/003-scp-design-philosophy.md), [Account management](docs/adrs/004-account-management-strategy.md), [OU hierarchy](docs/adrs/005-ou-hierarchy-design.md), [State bootstrap pattern](docs/adrs/006-state-bootstrap-pattern.md)
- **Architecture**: [AWS Organizations](docs/architecture/aws-organizations.md), [Config hierarchy](docs/architecture/config-hierarchy.md)
- **Compliance**: [SCP control mapping](docs/compliance/scp-control-mapping.md) (SOC2, HIPAA, PCI-DSS, NIST, CIS)
- **Runbooks**: [Add AWS account](docs/runbooks/add-aws-account.md), [Modify SCPs](docs/runbooks/modify-scps.md), [SCP incident response](docs/runbooks/incident-scp-blocking.md)
- **Guides**: [Onboarding](docs/onboarding.md), [User guide](docs/user-guide.md), [Troubleshooting](docs/troubleshooting/aws-organizations.md)
