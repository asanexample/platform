# Platform

## Project Overview

Multi-cloud IaC platform using OpenTofu + Terragrunt. Targets AWS and Azure (GCP stubbed).

- **Shared modules** (`infra/modules/`): cilium, argocd, argocd-bootstrap, argocd-clusters, cert-manager, external-dns, external-secrets, gateway-config, tailscale, tailscale-admin, policy, vcluster
- **Cloud-specific modules**: `infra/modules/aws/*` (eks, networking, ssm-bastion, etc.), `infra/modules/azure/*` (aks_core, networking, key_vault, etc.)
- **Live configs**: `infra/live/{aws,azure}/` -- environment-specific Terragrunt units

## Deployment Ordering (AWS)

Full dependency graph:

```text
iam-roles ──┐
             ├─> eks -> cilium -> node-groups -> ssm-bastion
networking ─┘                        |
              route53 ───────────────┤
              eks-addons ────────────┤ (eks, cilium, nodes)
              cert-manager ──────────┤ (eks, nodes, r53)
              external-dns ──────────┤ (eks, nodes, r53)
              external-secrets ──────┤ (eks, nodes)
              secret-stores ─────────┤ (eks, nodes, ext-secrets)
                                     |
              argocd ────────────────┤ (eks, nodes)
              argocd-clusters ──────┤ (argocd, eks, nodes, preprod eks+iam-roles)
              tailscale ─────────────┤ (eks, nodes, ext-secrets)
              gateway-config ────────┘ (eks, cilium, cert-manager, ext-dns, argocd, r53)

tailscale-admin ─────────────────────── (no cluster deps, manages tailnet ACLs/OAuth)
cloudtrail ──────────────────────────── (no deps, secrets audit logging)

### Preprod dependency graph (minimal stack)

iam-roles ──┐
             ├─> eks -> cilium -> node-groups -> eks-addons
networking ─┘                        |
              external-secrets ──────┤ (eks, nodes)
              secret-stores ─────────┘ (eks, nodes, ext-secrets)
```

EKS uses BYOCNI (`bootstrap_self_managed_addons = false`), so Cilium must be deployed before node groups can join the cluster. EKS managed add-ons (coredns) are in a separate `eks-addons` unit that depends on cilium + node-groups, since addon pods need the CNI to schedule.

### Apply order

```bash
# From infra/live/aws/platform/us-east-1/platform/
terragrunt run --all apply    # handles DAG automatically
```

### Destroy order

**Pre-flight:** If the EKS API is private-only (Tailscale VPN access), enable the public endpoint before destroying K8s units so Terragrunt can reach the API:

```bash
aws eks update-cluster-config --name platform-use1-eks --region us-east-1 \
  --resources-vpc-config endpointPublicAccess=true --profile platform
# Wait ~5 min for endpoint update + DNS propagation
```

```bash
# Option 1: automatic (handles DAG in reverse)
# To skip route53: add --filter '!./route53'
terragrunt run --all destroy --filter-allow-destroy -- -auto-approve

# Option 2: manual (if run-all fails or you need to skip units)
# Destroy leaf nodes first, work backwards:
cd gateway-config && terragrunt destroy -auto-approve && cd ..
cd tailscale && terragrunt destroy -auto-approve && cd ..
cd argocd && terragrunt destroy -auto-approve && cd ..
cd secret-stores && terragrunt destroy -auto-approve && cd ..
cd ssm-bastion && terragrunt destroy -auto-approve && cd ..
cd cert-manager && terragrunt destroy -auto-approve && cd ..
cd external-dns && terragrunt destroy -auto-approve && cd ..
cd external-secrets && terragrunt destroy -auto-approve && cd ..
cd eks-addons && terragrunt destroy -auto-approve && cd ..
cd node-groups && terragrunt destroy -auto-approve && cd ..
cd cilium && terragrunt destroy -auto-approve && cd ..
cd eks && terragrunt destroy -auto-approve && cd ..
cd networking && terragrunt destroy -auto-approve && cd ..
cd cloudtrail && terragrunt destroy -auto-approve && cd ..
# tailscale-admin — destroy separately if tearing down the tailnet
# route53 — destroy separately if needed
```

All dependency blocks have `mock_outputs` so destroy works even if upstream dependencies are already gone.

### Preprod deploy order

```bash
# From infra/live/aws/preprod/us-east-1/platform/
# Step 1: bootstrap iam-roles (direct SSO, no role assumption)
AWS_PROFILE=preprod terragrunt apply -chdir=iam-roles

# Step 2+: remaining units (management SSO → PlatformDeployer in preprod)
AWS_PROFILE=management terragrunt apply -chdir=networking
AWS_PROFILE=management terragrunt apply -chdir=eks
AWS_PROFILE=management terragrunt apply -chdir=cilium
AWS_PROFILE=management terragrunt apply -chdir=node-groups
AWS_PROFILE=management terragrunt apply -chdir=eks-addons
AWS_PROFILE=management terragrunt apply -chdir=external-secrets
AWS_PROFILE=management terragrunt apply -chdir=secret-stores
```

### Preprod destroy order

```bash
# From infra/live/aws/preprod/us-east-1/platform/
cd secret-stores && terragrunt destroy -auto-approve && cd ..
cd external-secrets && terragrunt destroy -auto-approve && cd ..
cd eks-addons && terragrunt destroy -auto-approve && cd ..
cd node-groups && terragrunt destroy -auto-approve && cd ..
cd cilium && terragrunt destroy -auto-approve && cd ..
cd eks && terragrunt destroy -auto-approve && cd ..
cd networking && terragrunt destroy -auto-approve && cd ..
cd iam-roles && terragrunt destroy -auto-approve && cd ..
```

## Key Commands

```bash
# Plan/apply from any live unit directory
terragrunt plan
terragrunt apply

# Bootstrap the full platform stack from zero
AWS_PROFILE=management ./scripts/bootstrap-platform.sh

# Tear down the full platform stack
AWS_PROFILE=management ./scripts/teardown-platform.sh                # preserves Route53
AWS_PROFILE=management ./scripts/teardown-platform.sh --include-route53  # destroys everything

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

Cross-account access uses purpose-built IAM roles (see IAM Roles below). `OrganizationAccountAccessRole` retained as break-glass only.

## IAM Roles

| Role | Account | Purpose |
|------|---------|---------|
| **PlatformAdmin** | Platform, PreProd | kubectl, SSM tunnel, cluster debugging |
| **PlatformDeployer** | Platform, PreProd | Terragrunt apply, Helm/K8s providers |
| **DeveloperAccess** | Platform, PreProd | Namespace-scoped kubectl for developers |
| **TerraformStateAccess** | Management (851725353202) | S3 state bucket + DynamoDB lock table |
| **OrganizationAccountAccessRole** | All accounts | Break-glass only |

- Terragrunt providers assume **PlatformDeployer** (via root.hcl)
- Helm/K8s exec auth uses **PlatformDeployer** (via `include.base.locals.deployer_role_arn`)
- kubectl uses **PlatformAdmin** (`aws eks update-kubeconfig --role-arn ...PlatformAdmin`)
- State backend uses **TerraformStateAccess** (via root.hcl remote_state `role_arn`)

## Architecture Decisions

- **Cilium as CNI** across all clouds. The shared `cilium` module uses a `cloud_provider` variable.
- **SSM Session Manager** for private cluster access (no VPN needed).
- **Hubble TLS** uses `helm` method on AWS to avoid post-install hook chicken-and-egg issues with BYOCNI.
- **Node groups separated** from the EKS module to enforce deployment ordering (Cilium must be ready first).
- **EKS add-ons separated** into `eks-addons` unit — with BYOCNI, addon pods (coredns) can't schedule until CNI + nodes are ready, so they must be deployed after cilium and node-groups.
- **ArgoCD SSO via Dex + SAML** for AWS. Dex is built into ArgoCD's Helm chart and acts as a SAML-to-OIDC bridge. The SAML app in Identity Center is created manually (Terraform AWS provider doesn't support custom SAML apps). Group claims in the SAML assertion map to ArgoCD RBAC roles. The ArgoCD module remains cloud-agnostic — all SSO config is injected via `argocd_cm_extra` in the live unit.
- **Tailscale Operator** for developer VPN access to private EKS. Runs as a subnet router advertising the VPC CIDR (`10.100.0.0/16`) to the tailnet. Split DNS is managed by the `tailscale` K8s unit (not `tailscale-admin`) with a `depends_on` on the Connector, so it's only created after the subnet router is online. OAuth credentials sourced from AWS Secrets Manager via generated data source. Module is cloud-agnostic; only the live unit's provider config is AWS-specific.
