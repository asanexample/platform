# Infrastructure as Code

This directory contains the Infrastructure as Code (IaC) for the platform, managed with
**OpenTofu** + **Terragrunt** (CLI versions pinned in `/.tool-versions`). The platform is **AWS-only** today — the Azure and
GCP modules/live trees were removed. The shared Kubernetes modules are written
cloud-agnostically so a second cloud could be added without restructuring, but only AWS is
exercised.

## Repository Structure

```text
infra/
├── modules/                 # Reusable OpenTofu modules
│   ├── aws/                 # AWS-specific modules
│   ├── cloudflare/          # Cloudflare (DNS delegation)
│   └── <shared>/            # Cloud-agnostic modules (Cilium, ArgoCD, policy, crossplane, …)
├── live/aws/                # Environment-specific Terragrunt units (platform, preprod, prod, mgmt)
├── docs/                    # Infrastructure documentation (see 02-architecture-overview.md)
└── tests/aws/<module>/      # Terratest (Go) per module
```

## Getting Started

- Prerequisites: the CLI toolchain in `/.tool-versions` (OpenTofu, Terragrunt, AWS CLI) — `mise install` to match CI/prod; OpenTofu floor is `>= 1.6`.
- Plan/apply from any live unit directory:

  ```bash
  cd infra/live/aws/platform/us-east-1/platform/<unit>
  terragrunt plan
  terragrunt apply
  ```

- Bootstrap/teardown the whole stack with `platctl bootstrap` / `platctl teardown`.

## Documentation

The full configuration hierarchy, deployment ordering, IAM roles, architecture decisions,
and key commands live in the repo-root [`CLAUDE.md`](../CLAUDE.md) and under
[`infra/docs/`](docs/) (start with
[02-architecture-overview.md](docs/02-architecture-overview.md) and
[17-available-modules.md](docs/17-available-modules.md)).
