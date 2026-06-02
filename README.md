# Reference Platform

A **reference architecture and pattern library for platform engineering** — a blueprint for the kind of
**Internal Developer Platform (IDP)** an enterprise platform team builds so product teams get a Vercel-like
"push to ship" experience on top of governed, secure, compliant cloud.

It treats the **platform as a product**, not a pile of Terraform. Product teams self-serve through a
declarative contract ([`teams.hcl`](infra/live/aws/preprod/us-east-1/platform/teams.hcl)), ship along
**paved roads** (GitOps delivery + a signed software supply chain + per-PR preview environments), and move
fast inside **guardrails** — policy-as-code enforced at admission — instead of waiting on tickets. The
platform absorbs the cognitive load of cloud, networking, security, and compliance so developers focus on
their apps, while governance stays invariant by construction.

The running infrastructure — multi-account AWS, private EKS, GitOps, a self-hosted observability stack, a
signed supply chain — is real and production-shaped, but it is the **means, not the end**. The deliverable
is the set of **patterns, contracts, and decisions**: 45 [architecture decision records](docs/adrs/) and a
full [design-doc set](infra/docs/) you can study, adapt, or lift wholesale.

> **Cloud scope — multi-cloud by design, AWS-first in practice.** A cloud-agnostic Kubernetes/platform layer
> (`infra/modules/`) sits over per-cloud foundations (`infra/modules/aws/`). AWS is the only cloud
> implemented today; Azure/GCP are **deferred until the AWS reference is mature**, and the shared modules are
> written to be portable for that future.

## What it demonstrates

The platform-engineering capabilities an enterprise IDP needs — each implemented end-to-end and documented:

| Capability | How it shows up here |
|------------|----------------------|
| **Self-service via contract** | Teams declare identity, apps, hostnames, and AWS access in `teams.hcl`; the platform provisions namespaces, ECR repos, IAM, and policy from it ([ADR-031](docs/adrs/031-multi-app-tenant-model.md)). *This is the interim contract — the north star is portal-driven self-service; see [Where this is heading](#where-this-is-heading--the-back-stack).* |
| **Golden paths / paved roads** | GitOps delivery (ArgoCD), signed-digest promotion, and per-PR preview environments are the supported, opinionated route to production ([ADR-021](docs/adrs/021-argocd-for-gitops.md)/[032](docs/adrs/032-pr-preview-environments.md)) |
| **Guardrails, not gates** | Policy-as-code at every layer — org SCPs and Kyverno admission — lets teams move fast without breaking governance ([ADR-014](docs/adrs/014-kyverno-as-policy-engine.md)) |
| **Multi-tenancy** | Team identity decoupled from app identity; namespace isolation with default-deny networking, quotas, and per-team EKS Pod Identity for AWS access ([ADR-027](docs/adrs/027-hybrid-tenant-isolation-model.md)/[041](docs/adrs/041-pod-identity-for-tenant-workloads.md)) |
| **Defense in depth** | Layered controls — Organizations/SCPs → IAM (operate-not-author) → private networking → admission policy → runtime detection (Falco) — with **no static credentials** anywhere (IRSA / Pod Identity / OIDC) |
| **Supply-chain integrity** | cosign keyless signing + CycloneDX SBOM + SLSA Build L3 provenance, **verified at admission** per team ([ADR-042](docs/adrs/042-isolated-build-provenance-slsa-l3.md)) |
| **Compliance as a capability** | Workloads declare a `compliance_tier` (standard/HIPAA/PCI) that selects controls; SCPs mapped to SOC2/HIPAA/PCI/ISO/NIST/CIS ([ADR-013](docs/adrs/013-compliance-tier-model.md)) |
| **Self-hosted observability** | Prometheus + Grafana + durable, multi-tenant Mimir — metrics you own, ready for spoke tenants ([ADR-043](docs/adrs/043-self-hosted-observability-stack.md)/[044](docs/adrs/044-mimir-durable-multi-tenant-metrics.md)) |
| **Day-2 operability** | A purpose-built CLI (`platctl`) for DAG-aware bootstrap/teardown/validate; private cluster access via Tailscale or SSM ([ADR-038](docs/adrs/038-platctl-cli-for-platform-operations.md)) |

## Using this as a reference

- **Platform / DevEx engineers** adopting patterns — start with the [design docs](infra/docs/) (architecture,
  multi-tenancy, security, supply chain) and compose the [reusable modules](infra/modules/); `infra/live/`
  shows one opinionated composition.
- **Architects** evaluating an approach — the [46 ADRs](docs/adrs/) record *why* each choice was made, and
  what was rejected.
- **New team members** — the [Onboarding Guide](docs/onboarding.md) and the [Quick Start](#quick-start) below.

## Where this is heading — the BACK stack

Today's self-service is a **declarative contract** (`teams.hcl`) reconciled by the platform team via
Terragrunt. That's deliberate — the **thinnest viable platform** that proves the tenancy, security, and
supply-chain model first. With that foundation in place, the next phase is true developer self-service on the
**BACK stack**:

| | Role | Status |
|---|------|--------|
| **B — [Backstage](https://backstage.io/)** | Internal Developer Portal — service catalog + software templates; the self-service front door (replaces hand-edited `teams.hcl` onboarding) | Planned |
| **A — ArgoCD** | GitOps reconciliation engine | **In place** |
| **C — [Crossplane](https://www.crossplane.io/)** | Infrastructure control plane — tenant capabilities (namespaces, ECR, IAM, Pod Identity, policy) modeled as Compositions/XRDs and **claimed through the Kubernetes API**, continuously reconciled (replaces Terragrunt for tenant-facing provisioning) | Planned |
| **K — Kubernetes** | The universal control plane everything rides on | **In place** |

The end state: a developer picks a Backstage template, which scaffolds a repo and a Crossplane claim; ArgoCD
applies it; Crossplane provisions the resources; Kubernetes runs them — portal-driven, GitOps-reconciled,
self-served. The patterns in this repo (multi-tenancy, policy-as-code, signed supply chain, observability)
are the substrate that stack composes onto. This work begins now that the foundation is established.

## Quick Start

```bash
# Prerequisites: OpenTofu 1.11, Terragrunt 1.x, AWS CLI v2, kubectl, helm

# Authenticate (SSO via IAM Identity Center)
aws sso login --profile management

# Bootstrap the full platform stack (DAG-aware)
platctl bootstrap

# Or deploy a single unit
cd infra/live/aws/platform/us-east-1/platform/eks
AWS_PROFILE=management terragrunt apply

# Validate deployed infrastructure
platctl validate

# Configure kubectl contexts
platctl kubeconfig
```

## Repository Layout

```text
platform/
├── cmd/platctl/                 # Go CLI for platform operations (bootstrap, teardown, validate, kubeconfig)
├── docs/                        # User-facing documentation
│   ├── adrs/                    # 46 architecture decision records
│   ├── architecture/            # System design, supply chain, observability, tenant model, config hierarchy
│   ├── compliance/              # SCP → control mapping
│   ├── runbooks/                # Operational procedures
│   └── troubleshooting/         # Known issues and solutions
├── infra/
│   ├── live/aws/                # Terragrunt live configurations (AWS only)
│   │   ├── mgmt/                # Management account (Organizations, SCPs, state, IAM Identity Center)
│   │   ├── platform/            # Platform account (EKS, ArgoCD, Tailscale, TGW hub, observability, ECR)
│   │   ├── preprod/             # Preprod account (EKS, tenants, ingress, TGW spoke)
│   │   ├── prod/                # Prod account (networking defined, not yet deployed)
│   │   └── test/               # Test account (GitHub OIDC sandbox for Terratest CI)
│   ├── modules/                 # Reusable OpenTofu modules
│   │   ├── aws/                 # 19 AWS modules
│   │   ├── cloudflare/          # 1 Cloudflare module (dns_delegation)
│   │   └── (shared)             # 18 cloud-agnostic modules (cilium, argocd, policy, observability, tenant, …)
│   ├── tests/                   # Terratest integration tests (Go)
│   └── root.hcl                 # Root Terragrunt config (S3 state, providers, terraform_binary)
└── scripts/                     # Helper scripts (eks-tunnel, bootstrap, teardown)
```

## AWS Accounts

Real account IDs live in `infra/live/aws/secrets.hcl` (gitignored; see `secrets.hcl.example`).

| Account | Purpose |
|---------|---------|
| **Management** | AWS Organizations, SCPs, IAM Identity Center (SSO), Terraform state (S3 + DynamoDB) |
| **Platform** | Shared services: EKS, ArgoCD, Tailscale, TGW hub, ECR, observability hub |
| **PreProd** | Workloads: EKS, tenant namespaces, public ingress, TGW spoke |
| **Prod** | Production workloads (networking defined, not yet deployed) |
| **Test** | GitHub OIDC sandbox for Terratest CI (`PlatformDeployer`-managed) |

Cross-account access uses purpose-built IAM roles (**PlatformAdmin** for operate/debug, **PlatformDeployer**
for Terragrunt apply, **DeveloperAccess-\<team\>** for namespace-scoped kubectl, **TerraformStateAccess** for
the state backend). `OrganizationAccountAccessRole` is retained as break-glass only. See [CLAUDE.md](CLAUDE.md)
and [ADR-040](docs/adrs/040-platform-engineer-access-model.md).

## Platform Stack

### Platform account — shared services cluster

- **EKS** (private API, BYOCNI) with **Cilium 1.19.4** (kube-proxy replacement, Gateway API, Hubble)
- **ArgoCD** for GitOps delivery, with Dex → IAM Identity Center SAML SSO
- **Observability hub** — kube-prometheus-stack (Prometheus + Grafana + Alertmanager), Grafana served
  Tailscale-only, `critical` alerts → SNS → email; **Grafana Mimir** as the durable, multi-tenant, S3-backed
  metrics store (Prometheus `remote_write`s to it)
- **Kyverno** policy engine — admission guardrails (pod hardening, multi-tenancy isolation, supply-chain
  verification)
- **Tailscale Operator** for VPN access to the private clusters
- **Transit Gateway hub** + cross-VPC DNS for private cross-account EKS connectivity
- **Gateway API** (internal NLB) for platform service ingress; cert-manager, ExternalDNS, External Secrets
  Operator

### Preprod account — workload cluster

- **EKS** with Cilium and Gateway API (public NLB)
- **Tenant isolation** via namespaces with default-deny NetworkPolicies, resource quotas, and per-team
  **EKS Pod Identity** for AWS access ([ADR-041](docs/adrs/041-pod-identity-for-tenant-workloads.md))
- **ArgoCD** Applications + per-team PR preview ApplicationSets
- **Kyverno in Enforce** — pod hardening **and** supply-chain verification (signatures + attestations)
- ECR cross-account image pull; GitHub OIDC for CI/CD

### Software supply chain (cross-cutting)

App CI (in the app repos) builds images, **cosign keyless-signs** them, attaches a **CycloneDX SBOM** and a
**SLSA Build L3** provenance attestation (signed by an isolated `trusted-ci` identity), then pins the deploy
manifest to the signed digest. **Kyverno verifies all of it at admission**, per team — only images signed by
the team's own CI, carrying a valid SBOM + provenance, are admitted. See
[Supply-Chain Overview](docs/architecture/supply-chain-overview.md).

### Compliance tiers

Workloads declare a `compliance_tier` (`standard` / `hipaa` / `pci`); the tier selects which Kyverno policies
and platform controls apply ([ADR-013](docs/adrs/013-compliance-tier-model.md)). Current clusters run the
`standard` tier.

### Deployment order

The full dependency DAG is documented in [CLAUDE.md](CLAUDE.md). The preferred deployment method is
`platctl bootstrap`, which resolves the DAG automatically.

## Modules

### Shared — cloud-agnostic (18)

| Module | Description |
|--------|-------------|
| [argocd](infra/modules/argocd/) | ArgoCD Helm deployment with RBAC, Dex SAML SSO, optional HA |
| [argocd-apps](infra/modules/argocd-apps/) | Multi-tenant AppProjects, Applications, PR preview ApplicationSets |
| [argocd-clusters](infra/modules/argocd-clusters/) | Remote cluster registration (hub → spokes) |
| [cert-manager](infra/modules/cert-manager/) | cert-manager Helm with IRSA for DNS-01 challenges |
| [cilium](infra/modules/cilium/) | Cilium CNI — BYOCNI, kube-proxy replacement, Gateway API, Hubble |
| [cluster-rbac](infra/modules/cluster-rbac/) | platform-operator ClusterRole — least-privilege kubectl (ADR-040) |
| [external-dns](infra/modules/external-dns/) | ExternalDNS Helm with IRSA |
| [external-secrets](infra/modules/external-secrets/) | External Secrets Operator Helm with IRSA |
| [falco](infra/modules/falco/) | Runtime threat detection (eBPF) — deployed on preprod ([ADR-045](docs/adrs/045-falco-runtime-threat-detection.md)) |
| [gateway-config](infra/modules/gateway-config/) | ClusterIssuer, Gateway, HTTPRoutes (TLS via cert-manager) |
| [observability](infra/modules/observability/) | Observability hub — kube-prometheus-stack + SNS alerting |
| [observability-mimir](infra/modules/observability-mimir/) | Durable, multi-tenant, S3-backed metrics store (Mimir) |
| [policy](infra/modules/policy/) | Kyverno engine + ClusterPolicies — pod hardening, multi-tenancy, image verification (ADR-014) |
| [secret-stores](infra/modules/secret-stores/) | ClusterSecretStore for AWS Secrets Manager and SSM |
| [tailscale](infra/modules/tailscale/) | Tailscale Operator, subnet router, split DNS |
| [tailscale-admin](infra/modules/tailscale-admin/) | Tailnet ACL and OAuth client management |
| [tenant](infra/modules/tenant/) | Namespace isolation — quotas, limits, NetworkPolicies, Pod Identity (ADR-041) |
| [vcluster](infra/modules/vcluster/) | vCluster Helm (deferred — ADR-033) |

### AWS (19)

| Module | Description |
|--------|-------------|
| [cloudtrail](infra/modules/aws/cloudtrail/) | Audit logging with S3, KMS, secrets alarms |
| [cross-vpc-dns](infra/modules/aws/cross-vpc-dns/) | Cross-VPC DNS for private EKS endpoints |
| [ecr](infra/modules/aws/ecr/) | ECR with lifecycle policies and cross-account access |
| [eks](infra/modules/aws/eks/) | EKS cluster with BYOCNI, KMS, OIDC, access entries |
| [eks-addons](infra/modules/aws/eks-addons/) | EKS managed add-ons + gp3 default StorageClass |
| [eks-node-group](infra/modules/aws/eks-node-group/) | EKS managed node groups |
| [eks-pod-identity](infra/modules/aws/eks-pod-identity/) | EKS Pod Identity associations for tenant AWS access (ADR-041) |
| [github_oidc](infra/modules/aws/github_oidc/) | GitHub Actions OIDC federation (ADR-036) |
| [iam_roles](infra/modules/aws/iam_roles/) | Purpose-built cross-account IAM roles |
| [identity_center](infra/modules/aws/identity_center/) | IAM Identity Center permission sets |
| [networking](infra/modules/aws/networking/) | VPC, subnets, NAT, flow logs (3 topology modes) |
| [organizations](infra/modules/aws/organizations/) | AWS Organizations with OUs and SCPs |
| [route53](infra/modules/aws/route53/) | Route53 hosted zones |
| [route53_delegation](infra/modules/aws/route53_delegation/) | NS record delegation between zones |
| [s3](infra/modules/aws/s3/) | General-purpose S3 buckets (SSE, public-access-blocked) |
| [sns-notifications](infra/modules/aws/sns-notifications/) | SNS alert topic (Alertmanager → email) |
| [ssm-bastion](infra/modules/aws/ssm-bastion/) | SSM bastion for private cluster access |
| [state_bootstrap](infra/modules/aws/state_bootstrap/) | S3 + DynamoDB for Terraform state |
| [transit-gateway](infra/modules/aws/transit-gateway/) | TGW hub/spoke for cross-VPC connectivity |

Plus [cloudflare/dns_delegation](infra/modules/cloudflare/dns_delegation/) (DNS delegation). Full catalog:
[infra/modules/README.md](infra/modules/README.md).

## Key Design Decisions

| Decision | ADR |
|----------|-----|
| Cilium as CNI (BYOCNI) | [ADR-008](docs/adrs/008-cilium-as-cross-cloud-cni.md) |
| EKS component separation (BYOCNI ordering) | [ADR-009](docs/adrs/009-eks-component-separation.md) |
| Private EKS API endpoint | [ADR-010](docs/adrs/010-private-eks-api-endpoint.md) |
| Tailscale for VPN access | [ADR-011](docs/adrs/011-tailscale-for-private-cluster-access.md) |
| Compliance-tier model | [ADR-013](docs/adrs/013-compliance-tier-model.md) |
| Kyverno as policy engine | [ADR-014](docs/adrs/014-kyverno-as-policy-engine.md) |
| Gateway API over Ingress | [ADR-017](docs/adrs/017-gateway-api-over-ingress.md) |
| ArgoCD for GitOps | [ADR-021](docs/adrs/021-argocd-for-gitops.md) |
| Namespace tenant isolation | [ADR-027](docs/adrs/027-hybrid-tenant-isolation-model.md) |
| Centralized cross-account ECR | [ADR-028](docs/adrs/028-ecr-cross-account-container-registry.md) |
| Multi-app tenant model | [ADR-031](docs/adrs/031-multi-app-tenant-model.md) |
| PR preview environments | [ADR-032](docs/adrs/032-pr-preview-environments.md) |
| Transit Gateway hub/spoke | [ADR-034](docs/adrs/034-transit-gateway-cross-account-connectivity.md) |
| GitHub Actions OIDC federation | [ADR-036](docs/adrs/036-github-actions-oidc-federation.md) |
| platctl CLI | [ADR-038](docs/adrs/038-platctl-cli-for-platform-operations.md) |
| Platform-engineer access model | [ADR-040](docs/adrs/040-platform-engineer-access-model.md) |
| Pod Identity for tenant workloads | [ADR-041](docs/adrs/041-pod-identity-for-tenant-workloads.md) |
| Isolated build provenance (SLSA L3) | [ADR-042](docs/adrs/042-isolated-build-provenance-slsa-l3.md) |
| Self-hosted observability stack | [ADR-043](docs/adrs/043-self-hosted-observability-stack.md) |
| Mimir for durable multi-tenant metrics | [ADR-044](docs/adrs/044-mimir-durable-multi-tenant-metrics.md) |
| Falco for runtime threat detection | [ADR-045](docs/adrs/045-falco-runtime-threat-detection.md) |
| BACK stack for developer self-service | [ADR-046](docs/adrs/046-back-stack-for-developer-self-service.md) |

All 46 ADRs: [docs/adrs/](docs/adrs/)

## Testing

Tests use **Terratest (Go)** and live in `infra/tests/aws/<module>/`. Plan-only tests cover modules that
can't be safely apply/destroyed in CI; tests must use the OpenTofu binary (`TerraformBinary: "tofu"`).

```bash
cd infra/tests/aws/networking && go test -v -timeout 30m
```

CI (GitHub Actions) runs OpenTofu/Terragrunt format, validate, TFLint, Kyverno policy tests, and security
scanning (Trivy IaC, Semgrep) — via OIDC federation, no stored credentials.

## Documentation

| Document | Description |
|----------|-------------|
| [Documentation Index](docs/README.md) | Full doc map — start here |
| [Onboarding Guide](docs/onboarding.md) | New team member quickstart |
| [User Guide](docs/user-guide.md) | Complete reference for deployments and day-2 ops |
| [Supply-Chain Overview](docs/architecture/supply-chain-overview.md) | cosign + SBOM + SLSA L3 + Kyverno, end to end |
| [Observability Current State](docs/architecture/observability-current-state.md) | As-built Prometheus/Grafana/Mimir hub |
| [Deploy App to Preprod](docs/runbooks/deploy-app-preprod.md) | Developer guide: manifests, ECR, ArgoCD |
| [App Supply-Chain Onboarding](docs/runbooks/app-supply-chain-onboarding.md) | Wire signing/SBOM/provenance into app CI |
| [Tenant Onboarding](docs/runbooks/tenant-onboarding.md) | Add/remove teams via `teams.hcl` |
| [EKS Cluster Access](docs/runbooks/eks-cluster-access.md) | kubectl setup for engineers |
| [Architecture Decisions](docs/adrs/) | 46 ADRs documenting every significant choice |
