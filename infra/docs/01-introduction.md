# Introduction

## Overview

The platform is an infrastructure solution built with OpenTofu and
Terragrunt. It is **multi-cloud by design but AWS-first today** — only AWS is
deployed; Azure and GCP are planned and the shared modules/structure are
parameterized for them. It provides standardized, repeatable infrastructure with
consistent patterns for networking, security, Kubernetes, and operations.

## Goals

1. **Multi-cloud by design, AWS-first** -- cloud-agnostic shared modules (Cilium,
   ArgoCD, cert-manager) plus cloud-specific modules, so Azure/GCP can be added
   without restructuring. Only AWS is deployed today.
2. **Security by design** -- SCPs, private endpoints, RBAC,
   least-privilege IAM, encryption at rest and in transit.
3. **Kubernetes-first** -- EKS clusters with Cilium CNI (BYOCNI) and ArgoCD
   GitOps. Standard tenants use **namespace isolation** (vCluster deferred, ADR-033).
4. **Hierarchical configuration** -- a 6-layer Terragrunt hierarchy that
   composes tags, CIDRs, and module inputs from broad defaults to
   unit-specific overrides.
5. **Testable infrastructure** -- Terratest (Go) for module integration tests,
   with CI validation (fmt/validate/lint/policy) on every PR.

## Project Structure

```text
platform/
├── CLAUDE.md                    # Deployment ordering, key commands
├── docs/                        # ADRs, runbooks, onboarding
├── infra/
│   ├── docs/                    # This reference documentation
│   ├── modules/                 # Reusable modules (AWS only today; azure/, gcp/ planned)
│   │   ├── aws/                 # AWS-specific (EKS, networking, IAM, ECR, organizations, ...)
│   │   ├── cloudflare/          # DNS delegation
│   │   ├── cilium/              # Shared: CNI
│   │   ├── argocd/ argocd-apps/ # Shared: GitOps
│   │   ├── cert-manager/        # Shared: TLS certificates
│   │   ├── external-dns/        # Shared: DNS record sync
│   │   ├── external-secrets/    # Shared: secret injection (+ secret-stores)
│   │   ├── tailscale/           # Shared: VPN operator (+ tailscale-admin)
│   │   ├── gateway-config/      # Shared: Gateway API ingress
│   │   ├── policy/              # Shared: Kyverno
│   │   ├── observability/       # Shared: kube-prometheus-stack (+ observability-mimir)
│   │   ├── tenant/ cluster-rbac/ eks-pod-identity/   # Shared: multi-tenancy + RBAC + Pod Identity
│   │   └── vcluster/            # Shared: virtual clusters (deferred, ADR-033)
│   ├── live/                    # Environment-specific Terragrunt configs
│   │   └── aws/                 # 5 accounts (mgmt, platform, test, preprod, prod)
│   │                           #   (live/azure, live/gcp are planned, not present)
│   ├── tests/
│   │   └── aws/                 # Terratest (Go)
│   └── scripts/
│       └── eks-tunnel.sh        # SSM tunnel to private EKS
├── cmd/platctl/                 # platctl orchestration CLI (Go, ADR-038)
├── scripts/                     # Helper scripts (e.g. scaffold-region.sh)
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
