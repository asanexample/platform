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
| [Preprod Tenant Model](architecture/preprod-tenant-model.md) | Namespace-based tenant isolation architecture |
| [Config Hierarchy](../infra/live/aws/_base.hcl) | Seven-layer Terragrunt configuration precedence (root through module) |
| [Module Design](../infra/docs/13-module-design.md) | Conventions for writing and consuming infrastructure modules |

## How-To Guides

| Document | Description |
|----------|-------------|
| [Runbooks](runbooks/) | Step-by-step operational procedures for common tasks |
| [Deploy App to Preprod](runbooks/deploy-app-preprod.md) | Developer guide: repo structure, manifests, ECR push, ArgoCD sync |
| [Tenant Onboarding](runbooks/tenant-onboarding.md) | Platform team: onboard/offboard teams, choose isolation mode |
| [EKS Cluster Access](runbooks/eks-cluster-access.md) | kubectl setup for platform engineers and developers |
| [ArgoCD SSO](runbooks/argocd-sso.md) | SSO setup, troubleshooting, and group-based RBAC |
| [User Guide](user-guide.md) | Greenfield and brownfield deployments, day-2 operations |
| [Troubleshooting](troubleshooting/) | Solutions to known issues and error patterns |

## Why (Decisions)

| Document | Description |
|----------|-------------|
| [ADRs](adrs/) | Architecture Decision Records explaining key design choices |
| [ADR-007: IAM Role Model](adrs/007-iam-role-model.md) | Purpose-built IAM roles replacing OrganizationAccountAccessRole |
| [ADR-027: Hybrid Tenant Isolation](adrs/027-hybrid-tenant-isolation-model.md) | Namespace isolation model for preprod (vCluster deferred) |
| [ADR-028: ECR Cross-Account Registry](adrs/028-ecr-cross-account-container-registry.md) | Centralized ECR with cross-account pull |
| [ADR-029: Preprod Public Ingress](adrs/029-preprod-public-ingress-gateway-api.md) | Public Gateway API ingress for preprod |
| [ADR-030: Route53 Subdomain Delegation](adrs/030-route53-subdomain-delegation.md) | Per-environment DNS zones with NS delegation |
| [ADR-031: Multi-App Tenant Model](adrs/031-multi-app-tenant-model.md) | Nested apps per team in teams.hcl, ECR naming convention |
| [ADR-032: PR Preview Environments](adrs/032-pr-preview-environments.md) | ArgoCD ApplicationSet PR generator for ephemeral previews |
| [ADR-033: Defer vCluster Support](adrs/033-defer-vcluster-tenant-support.md) | vCluster deferred — OSS lacks HTTPRoute sync |
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
