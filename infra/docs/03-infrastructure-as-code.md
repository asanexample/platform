# Infrastructure as Code Approach

## Overview

All infrastructure is defined in OpenTofu modules managed by Terragrunt.
No resources are created manually. The codebase is organized into
reusable modules, cloud-specific live configurations, and automated tests.

## Tools

| Tool | Role |
|------|------|
| [OpenTofu](https://opentofu.org/) >= 1.6.0 | Infrastructure definition and provisioning (open-source Terraform fork) |
| [Terragrunt](https://terragrunt.gruntwork.io/) | DRY configuration, remote state, dependency orchestration, provider generation |
| [Terratest](https://terratest.gruntwork.io/) | Go-based infrastructure testing (AWS) |
| `terraform test` | Native `.tftest.hcl` testing (Azure) |

All modules use the `tofu` binary, not `terraform`. This is configured in
`infra/root.hcl`.

## Project Structure

```text
infra/
├── modules/                        # Reusable modules
│   ├── aws/                        # AWS-specific (12 modules)
│   │   ├── eks/
│   │   ├── networking/
│   │   ├── organizations/
│   │   └── ...
│   ├── azure/                      # Azure-specific (24 modules)
│   │   ├── aks_core/
│   │   ├── networking/
│   │   └── ...
│   ├── gcp/                        # GCP-specific (2 modules)
│   │   ├── naming/
│   │   └── networking/
│   ├── cloudflare/                 # DNS delegation
│   ├── cilium/                     # Shared: CNI
│   ├── argocd/                     # Shared: GitOps
│   ├── cert-manager/               # Shared: TLS
│   ├── external-dns/               # Shared: DNS sync
│   ├── external-secrets/           # Shared: secret injection
│   ├── tailscale/                  # Shared: VPN operator
│   ├── tailscale-admin/            # Shared: tailnet config
│   ├── gateway-config/             # Shared: ingress
│   ├── policy/                     # Shared: Kyverno
│   └── vcluster/                   # Shared: virtual clusters
├── live/                           # Environment-specific configs
│   ├── aws/
│   │   ├── _base.hcl              # Config composer
│   │   ├── _versions.hcl          # Module sources + Helm pins
│   │   ├── common.hcl             # Cloud-level defaults
│   │   ├── mgmt/                  # Management account
│   │   ├── platform/              # Platform account
│   │   ├── preprod/               # Pre-production
│   │   └── prod/                  # Production
│   ├── azure/
│   │   ├── _base.hcl
│   │   ├── _versions.hcl
│   │   ├── _envcommon/            # Shared module defaults
│   │   ├── dev/
│   │   └── ops/
│   └── gcp/
│       ├── _base.hcl
│       └── ops/                   # Scaffolded, not deployed
├── tests/
│   ├── aws/                       # Terratest (Go)
│   └── modules/azure/             # Native .tftest.hcl
└── docs/                          # This documentation
```

### Modules vs Live

**Modules** (`infra/modules/`) are reusable, parameterized components.
They accept variables, create resources, and produce outputs. Modules
are cloud-agnostic where possible (Cilium, ArgoCD) or cloud-specific
where necessary (EKS, AKS).

**Live configs** (`infra/live/`) are environment-specific Terragrunt
units that compose modules with concrete values. Each `terragrunt.hcl`
selects a module source, declares dependencies, and passes inputs.

### Shared vs Cloud-Specific Modules

Shared modules (top level of `infra/modules/`) deploy Helm charts or
Kubernetes manifests that work on any cluster. They accept OAuth
credentials, IRSA role ARNs, or other identity primitives as variables
-- the live unit handles sourcing these from cloud-specific stores.

Cloud-specific modules live under `infra/modules/{aws,azure,gcp}/` and
use cloud-native resources (VPCs, AKS clusters, IAM roles, etc.).

## Configuration Hierarchy

Terragrunt uses a 7-layer configuration hierarchy that composes values
from broad defaults down to module-specific overrides:

```text
root.hcl          → State backend, providers, OpenTofu binary
common.hcl        → Cloud-wide tags, account/subscription maps
_versions.hcl     → Module source paths, Helm chart version pins
env.hcl           → Account ID, environment name, env tags
region.hcl        → Region name, AZs
workload.hcl      → Workload name, compliance tier
terragrunt.hcl    → Module source, dependencies, inputs
```

`_base.hcl` loads all layers, merges tags, runs safety validations
(environment path matches env.hcl, account ID matches safety map), and
exposes composed values to modules via `include.base.locals.*`.

For the full breakdown, see
[Terragrunt Configuration Hierarchy](../../docs/architecture/config-hierarchy.md).

## Module Structure

Every module follows the same file layout:

```text
module-name/
├── main.tf           # Resources and locals
├── variables.tf      # Input variables
├── outputs.tf        # Output values
└── versions.tf       # Required providers
```

Key conventions:

- **`create` toggle** -- every module accepts a `var.create` boolean
  (default `true`) that gates all resources via `count`. This allows
  disabling a module without removing its live unit.
- **`tags` variable** -- `map(string)`, default `{}`. Resources merge
  `var.tags` with a resource-specific `Name` tag.
- **No hardcoded providers** -- modules declare required providers in
  `versions.tf` but never configure them. Provider configuration is
  generated by Terragrunt.

For design patterns and anti-patterns, see
[Module Design](13-module-design.md).

## Version Management

`_versions.hcl` (one per cloud) is the single source of truth for module
sources and Helm chart versions:

```hcl
module_source = {
  networking = "${local.source_base}/aws//networking"
  eks        = "${local.source_base}/aws//eks"
  cilium     = "${local.source_base}/cilium"
  # ...
}

helm_versions = {
  cilium             = "1.17.2"
  argocd             = "9.5.14"
  cert_manager       = "1.17.1"
  # ...
}
```

All sources use `get_repo_root()` so paths resolve correctly regardless
of working directory. When the project migrates to a registry, only
`_versions.hcl` needs to change.

## Dependency Management

Terragrunt `dependency` blocks define the deployment graph. Each
dependency declares `mock_outputs` so that `destroy` works even when
upstream dependencies are already gone:

```hcl
dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    cluster_endpoint = "https://mock"
    cluster_ca       = "mock-ca"
    cluster_id       = "mock-cluster"
  }
}
```

`terragrunt run --all apply` resolves the full DAG and deploys in
order. `terragrunt run --all destroy` reverses the graph.

See the AWS and Azure dependency graphs in
[Architecture Overview](02-architecture-overview.md).

## State Management

State is routed automatically by `root.hcl` based on the cloud directory:

| Cloud | Backend | Location |
|-------|---------|----------|
| AWS | S3 + DynamoDB | `tfstate-mgmt-851725353202`, `terraform-locks` |
| Azure/GCP | Azure Blob | `tfstatemulticloud`, `terraformstate` container |

State keys mirror the directory structure:
`live/aws/platform/us-east-1/platform/eks/terraform.tfstate`.

For details, see
[Configuration Hierarchy: Cloud-Aware Remote State Routing](../../docs/architecture/config-hierarchy.md#cloud-aware-remote-state-routing).

## Development Workflow

### Adding a Module

1. Create the module in `infra/modules/` with `main.tf`, `variables.tf`,
   `outputs.tf`, `versions.tf`.
2. Add the module source to `_versions.hcl`.
3. Create a live unit in `infra/live/{cloud}/{env}/{region}/{workload}/`.
4. Write tests in `infra/tests/`.

### Deploying

```bash
# Single module
cd infra/live/aws/platform/us-east-1/platform/eks
terragrunt plan
terragrunt apply

# Full stack (DAG order)
cd infra/live/aws/platform/us-east-1/platform
terragrunt run --all apply
```

### Testing

```bash
# AWS (Terratest)
cd infra/tests/aws
go test -v -timeout 30m ./networking/...

# Azure (native)
cd infra/tests/modules/azure/aks_core
terraform init && terraform test
```

For the full testing strategy, see [Testing Strategy](15-testing-strategy.md).

### CI

Every PR runs format checks (`tofu fmt`, `terragrunt hcl fmt`),
validation (`tofu validate` on all modules), linting (`tflint`), and
markdown linting. Integration tests run weekly on a schedule. See
[Testing Strategy: CI Integration](15-testing-strategy.md#ci-integration).

## Next Steps

Continue to [Multi-Cloud Strategy](04-multi-cloud-strategy.md) to
understand how the platform implements consistent patterns across cloud
providers.
