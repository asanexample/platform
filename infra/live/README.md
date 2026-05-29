# Terragrunt Live Configurations

This directory contains all environment-specific Terragrunt configurations that
compose our infrastructure using the reusable modules from `/infra/modules/`.

## Directory Structure

```text
live/
├── aws/
│   ├── common.hcl            # Shared variables for all AWS environments
│   ├── _base.hcl             # Seven-layer config hierarchy (included by all units)
│   ├── _versions.hcl         # Helm chart version pins
│   ├── mgmt/                 # Management account (Organizations, state, IAM Identity Center)
│   │   ├── env.hcl
│   │   └── global/
│   │       ├── organizations/
│   │       ├── identity-center/
│   │       ├── state-bootstrap/
│   │       └── state-access/
│   ├── platform/             # Platform account (shared services)
│   │   ├── env.hcl
│   │   └── us-east-1/
│   │       ├── region.hcl
│   │       └── platform/     # EKS, networking, ArgoCD, Tailscale, TGW hub, etc.
│   └── preprod/              # Preprod account (workload environments)
│       ├── env.hcl
│       └── us-east-1/
│           ├── region.hcl
│           └── platform/     # EKS, networking, tenants, TGW spoke, etc.
```

## Configuration Hierarchy

Each Terragrunt unit includes `_base.hcl`, which loads and merges configuration
from seven layers (highest precedence last):

1. `root.hcl` — backend, provider generation, common tags
2. `common.hcl` — AWS-wide settings (account map, SSO config)
3. `env.hcl` — account ID, environment name
4. `region.hcl` — region, AZs
5. `network.hcl` — VPC CIDR, subnet layout
6. `workload.hcl` — workload-specific overrides
7. Unit `terragrunt.hcl` — module source, inputs, dependencies

## Getting Started

```bash
# Navigate to any unit directory
cd infra/live/aws/platform/us-east-1/platform/eks

# Plan
AWS_PROFILE=management terragrunt plan

# Apply
AWS_PROFILE=management terragrunt apply
```

See [Onboarding Guide](../../docs/onboarding.md) for prerequisites and setup.

## State Management

All Terraform state is stored in S3 with DynamoDB locking, configured in
`root.hcl`. Each unit has its own state file keyed by its path relative to
`root.hcl`.

## Dependency Management

Terragrunt manages dependencies via `dependency` blocks. Run `terragrunt graph`
from any unit to visualize its dependency tree. See `CLAUDE.md` for the full
deploy and destroy ordering.
