# Introduction

## Overview

The platform is a multi-cloud infrastructure solution built with
OpenTofu and Terragrunt. It provides standardized, repeatable
infrastructure across AWS, Azure, and GCP with consistent patterns for
networking, security, Kubernetes, and operations.

## Goals

1. **Multi-cloud deployment** -- consistent patterns across AWS, Azure,
   and GCP using shared modules (Cilium, ArgoCD, cert-manager) and
   cloud-specific modules where necessary.
2. **Security by design** -- SCPs, private endpoints, RBAC,
   least-privilege IAM, encryption at rest and in transit.
3. **Kubernetes-first** -- EKS and AKS clusters with Cilium CNI,
   ArgoCD GitOps, and vCluster multi-tenancy for standard workloads.
4. **Hierarchical configuration** -- 7-layer Terragrunt hierarchy that
   composes tags, CIDRs, and module inputs from broad defaults to
   module-specific overrides.
5. **Testable infrastructure** -- Terratest (Go) for AWS, native
   `.tftest.hcl` for Azure, CI validation on every PR.

## Project Structure

```text
platform/
├── CLAUDE.md                    # Deployment ordering, key commands
├── docs/                        # ADRs, runbooks, onboarding
├── infra/
│   ├── docs/                    # This reference documentation
│   ├── modules/                 # Reusable modules
│   │   ├── aws/                 # AWS-specific (EKS, networking, IAM, etc.)
│   │   ├── azure/               # Azure-specific (AKS, storage, Front Door, etc.)
│   │   ├── gcp/                 # GCP-specific (naming, networking)
│   │   ├── cloudflare/          # DNS delegation
│   │   ├── cilium/              # Shared: CNI
│   │   ├── argocd/              # Shared: GitOps
│   │   ├── cert-manager/        # Shared: TLS certificates
│   │   ├── external-dns/        # Shared: DNS record sync
│   │   ├── external-secrets/    # Shared: secret injection
│   │   ├── tailscale/           # Shared: VPN operator
│   │   ├── tailscale-admin/     # Shared: tailnet config
│   │   ├── gateway-config/      # Shared: ingress
│   │   ├── policy/              # Shared: Kyverno
│   │   └── vcluster/            # Shared: virtual clusters
│   ├── live/                    # Environment-specific Terragrunt configs
│   │   ├── aws/                 # 5 accounts (mgmt, platform, test, preprod, prod)
│   │   ├── azure/               # 2 subscriptions (dev, ops)
│   │   └── gcp/                 # Scaffolded (ops)
│   ├── tests/
│   │   ├── aws/                 # Terratest (Go)
│   │   └── modules/azure/       # Native .tftest.hcl
│   └── scripts/
│       └── eks-tunnel.sh        # SSM tunnel to private EKS
├── scripts/
│   └── scaffold-region.sh       # Region scaffolding tool
└── .github/workflows/           # CI (format, validate, lint, tests)
```

## Getting Started

1. [Architecture Overview](02-architecture-overview.md) -- design
   principles, deployment status, dependency graphs
2. [Infrastructure as Code](03-infrastructure-as-code.md) -- project
   layout, module structure, development workflow
3. [Available Modules](17-available-modules.md) -- complete module catalog
4. [Module Design](13-module-design.md) -- conventions for writing modules
5. [Testing Strategy](15-testing-strategy.md) -- how to test modules

For operational tasks, see the [runbooks](../../docs/runbooks/) in `docs/`.

## Next Steps

Continue to the [Architecture Overview](02-architecture-overview.md) for
design principles and the current deployment state.
