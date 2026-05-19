# Platform

## Project Overview

Multi-cloud IaC platform using OpenTofu + Terragrunt. Targets AWS and Azure (GCP stubbed).

- **Shared modules** (`infra/modules/`): cilium, argocd, argocd-bootstrap, policy, vcluster
- **Cloud-specific modules**: `infra/modules/aws/*` (eks, networking, ssm-bastion, etc.), `infra/modules/azure/*` (aks_core, networking, key_vault, etc.)
- **Live configs**: `infra/live/{aws,azure}/` -- environment-specific Terragrunt units

## Deployment Ordering (AWS)

Each step depends on the previous:

```text
networking -> eks -> cilium -> node-groups -> ssm-bastion -> argocd
```

EKS uses BYOCNI (`bootstrap_self_managed_addons = false`), so Cilium must be deployed before node groups can join the cluster.

## Key Commands

```bash
# Plan/apply from any live unit directory
terragrunt plan
terragrunt apply

# Format checks
tofu fmt -check -recursive infra/modules/
terragrunt hclfmt --check

# Tests (Terratest, Go)
cd infra/tests/aws/<module> && go test -v -timeout 30m

# Private cluster access
./scripts/eks-tunnel.sh <cluster-name> <region>
```

## Pre-commit Hooks

`.githooks/pre-commit` runs tofu fmt, terragrunt hclfmt, and tofu validate on staged files. Activate with:

```bash
git config core.hooksPath .githooks
```

## Testing Conventions

- Terratest (Go) for all modules. Tests live in `infra/tests/aws/<module>/`.
- Plan-only tests for modules that cannot be safely apply/destroyed in CI.
- Test fixtures in `infra/tests/aws/<module>/fixtures/`.
- Must use OpenTofu binary: set `TerraformBinary: "tofu"` in test options.

## AWS Accounts

| Account    | ID           |
|------------|--------------|
| Management | 851725353202 |
| Platform   | 829808296602 |
| PreProd    | 620830101009 |
| Prod       | 554518885123 |

Cross-account access via `OrganizationAccountAccessRole`.

## Architecture Decisions

- **Cilium as CNI** across all clouds. The shared `cilium` module uses a `cloud_provider` variable.
- **SSM Session Manager** for private cluster access (no VPN needed).
- **Hubble TLS** uses `helm` method on AWS to avoid post-install hook chicken-and-egg issues with BYOCNI.
- **Node groups separated** from the EKS module to enforce deployment ordering (Cilium must be ready first).
