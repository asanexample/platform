# Documentation Index

This repository manages multi-cloud infrastructure (AWS, Azure, GCP) using
OpenTofu modules orchestrated by Terragrunt. All cloud resources are defined
declaratively, version-controlled, and deployed through a layered configuration
hierarchy that promotes consistency across environments.

## Start Here

| Document | Description |
|----------|-------------|
| [Onboarding Guide](onboarding.md) | New team member quickstart: prerequisites, first deploy, daily workflows |
| [User Guide](user-guide.md) | Complete reference for module configuration, deployments, and day-2 operations |

## How It Works

| Document | Description |
|----------|-------------|
| [Architecture](architecture/) | System design, network topology, and multi-cloud strategy |
| [Config Hierarchy](../infra/live/aws/_base.hcl) | Seven-layer Terragrunt configuration precedence (root through module) |
| [Module Design](../infra/docs/13-module-design.md) | Conventions for writing and consuming infrastructure modules |

## How-To Guides

| Document | Description |
|----------|-------------|
| [Runbooks](runbooks/) | Step-by-step operational procedures for common tasks |
| [EKS Cluster Access](runbooks/eks-cluster-access.md) | kubectl setup for platform engineers and developers |
| [User Guide](user-guide.md) | Greenfield and brownfield deployments, day-2 operations |
| [Troubleshooting](troubleshooting/) | Solutions to known issues and error patterns |

## Why (Decisions)

| Document | Description |
|----------|-------------|
| [ADRs](adrs/) | Architecture Decision Records explaining key design choices |
| [ADR-007: IAM Role Model](adrs/007-iam-role-model.md) | Purpose-built IAM roles replacing OrganizationAccountAccessRole |
| [Compliance Framework](compliance/) | Regulatory mappings, SCP rationale, and audit evidence |

## Reference

| Document | Description |
|----------|-------------|
| [Organizations Module](../infra/modules/aws/organizations/README.md) | AWS Organizations, OUs, accounts, and Service Control Policies |
| [State Bootstrap Module](../infra/modules/aws/state_bootstrap/README.md) | S3 + DynamoDB remote state backend provisioning |
| [Variable Validation Standards](terraform/variable_validation_standards.md) | Conventions for OpenTofu variable validation rules |
| [Naming Conventions](../infra/docs/11-naming-conventions.md) | Resource naming patterns across all clouds |
| [Tagging Strategy](../infra/docs/12-tagging-strategy.md) | Required and recommended tags for cost allocation and compliance |
| [Available Modules](../infra/docs/17-available-modules.md) | Catalog of all infrastructure modules with status |

## Repository Layout (Quick Reference)

```text
docs/               You are here -- user-facing documentation
infra/modules/      Reusable OpenTofu modules (aws/, azure/, gcp/, shared)
infra/live/         Terragrunt live configurations per cloud/env/region/workload
infra/tests/        Module integration tests
infra/docs/         Infrastructure design documentation (numbered series)
infra/scripts/      Helper scripts and Terragrunt hooks
```
