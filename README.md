# Reference Platform

**Ship to your own governed cloud as fast as you'd ship to Vercel.**

Enterprises usually pick one or the other: let product teams move fast and lose the plot on security and
compliance, or keep control and bury everyone in tickets. This is a working reference platform that refuses the
trade. Developers self-serve through declarative, git-native contracts and ship along **paved roads** — while
governance holds **invariant by construction**, enforced at admission, not by review.

A developer's entire interaction is one declarative claim. From it, the platform reconciles the whole
footprint — namespace, RBAC, quotas, network policy, an ECR repo, scoped IAM, developer access, per-product
policy — and hands every app a **signed software supply chain**, **per-PR preview environments**, and **full
observability**, without them touching any of it. The platform absorbs the cognitive load of cloud,
networking, security, and compliance so developers think about their apps; governance stays out of their way
*and* never bends.

It treats the **platform as a product**, not a pile of Terraform. The running infrastructure — multi-account
AWS, private EKS, GitOps, a self-hosted LGTM+profiles observability stack, a signed supply chain — is real and
production-shaped. But the deliverable is the set of **patterns, contracts, and decisions**: **88
[architecture decision records](docs/adrs/)** and a full [design-doc set](infra/docs/) you can study, adapt, or
lift wholesale.

> **Cloud scope — multi-cloud by design, AWS-first in practice.** A cloud-agnostic Kubernetes/platform layer
> (`infra/modules/`) sits over per-cloud foundations (`infra/modules/aws/`). AWS is the only cloud implemented
> today; Azure/GCP are **deferred until the AWS reference is mature**, and the shared modules are written to be
> portable for that future.

## What shipping actually looks like

The whole point is the experience. When a developer ships a new service, here's what *they* do — and what the
platform does for them, invisibly:

1. **One form.** In the [Backstage](https://backstage.io/) portal, they pick the *New Product* template and fill
   in a team, product, and stage. The scaffolder opens a **gated pull request** that adds a `Product` registry
   entry and an `XEnvironment` claim (and, for a new service, a repo from the golden-path skeleton).
2. **Merge provisions everything.** ArgoCD applies the claim; a **Crossplane Composition** reconciles it into the
   complete environment footprint — namespace, RBAC, `ResourceQuota`, default-deny `NetworkPolicy`, an **ECR
   repo**, **scoped IAM via EKS Pod Identity** (no static keys), per-team `kubectl` access, and per-product
   admission policy. No tickets, no platform-team hand-offs.
3. **CI signs the artifact.** The app's CI is a *thin caller* of shared, app-team-unwritable `trusted-ci`
   workflows: build → **cosign keyless-sign** → **CycloneDX SBOM** → **SLSA Build L3 provenance** → pin the
   deploy manifest to the signed digest.
4. **The cluster enforces the rules.** **Kyverno** verifies all of it at admission — signature, SBOM, provenance,
   team-scoped image registry, an immutable tag, resource limits, probes, pod hardening, hostname allow-lists.
   Non-compliant workloads are *rejected*, not flagged.
5. **It runs, observed and previewed.** The service comes up behind the Cilium Gateway, gets **per-PR preview
   environments** automatically, and is **fully instrumented with zero code** — RED metrics, logs, distributed
   traces, and CPU profiles, with SLOs and a single Grafana pane spanning every cluster.

The result a developer feels is "I pushed and it shipped." Everything between steps 1 and 5 — the governance
that makes it safe — is the platform's job, done by construction.

## Governance by construction

What makes that speed *safe* is that the guardrails aren't optional and aren't manual. Delivery, policy, and
IAM are **derived** from the git-native `Team`/`Product`/`Environment`/`Release` registries (`gitops/`) — the
single source of truth; change the registry and the platform reconciles the consequences. And the rules are
**enforced at admission**, not in review: a workload missing a signature, an SBOM, resource limits, or a
team-scoped image registry is *rejected by the cluster*, not flagged in a PR. Governance is a property of the
system, not a step in a process.

## Capability matrix

The platform-engineering capabilities an enterprise IDP needs — each implemented end-to-end, with honest
status. **✅ Live** · **◐ Partial / modeled** · **○ Designed / deferred**.

| Capability | Status | How it works |
|---|:---:|---|
| **Self-service provisioning** | ✅ | One `XEnvironment` claim → a Crossplane Composition is its **sole provisioner** (namespace, RBAC, quotas, network policy, ECR, IAM, dev access, policy) ([ADR-046](docs/adrs/046-back-stack-for-developer-self-service.md)/[048](docs/adrs/048-federated-per-cluster-crossplane.md)/[067](docs/adrs/067-idp-domain-model.md)) |
| **GitOps delivery** | ✅ | ArgoCD + per-team AppProjects/RBAC; registries derive the Applications ([ADR-021](docs/adrs/021-argocd-for-gitops.md)) |
| **Golden paths & scaffolding** | ✅ | Backstage software templates; signed-digest promotion up a dev→test→staging→prod ladder, gated prod + SoD ([ADR-051](docs/adrs/051-backstage-developer-portal.md)/[071](docs/adrs/071-digest-promotion-via-control-plane.md)) |
| **PR preview environments** | ✅ | ArgoCD ApplicationSet PR generator — ephemeral envs per PR ([ADR-032](docs/adrs/032-pr-preview-environments.md)) |
| **Policy as code** | ✅ Enforce | Kyverno admission (pod hardening, isolation, supply-chain) **+** org SCPs; Enforce on platform + preprod ([ADR-014](docs/adrs/014-kyverno-as-policy-engine.md)) |
| **Software supply chain** | ✅ | cosign keyless + CycloneDX SBOM + SLSA Build L3, **verified at admission per team** ([ADR-042](docs/adrs/042-isolated-build-provenance-slsa-l3.md)/[050](docs/adrs/050-shared-build-sign-reusable-workflow.md)) |
| **Multi-tenancy & isolation** | ✅ | Ownership decoupled from the deployment unit; namespace + default-deny networking + quotas + per-team Pod Identity ([ADR-027](docs/adrs/027-hybrid-tenant-isolation-model.md)/[067](docs/adrs/067-idp-domain-model.md)) |
| **Identity & SSO** | ✅ | Keycloak OIDC across ArgoCD, Backstage, and Grafana; pluggable-IdP seam ([ADR-053](docs/adrs/053-identity-and-cross-system-authorization-strategy.md)/[059](docs/adrs/059-identity-topology-pluggable-idp-seam.md)) |
| **Secrets — zero static creds** | ✅ | External Secrets ↔ Secrets Manager; AWS access via Pod Identity / OIDC only ([ADR-047](docs/adrs/047-pod-identity-as-aws-identity-standard.md)) |
| **Networking** | ✅ | Cilium (kube-proxy-replacement, Gateway API, Hubble), private EKS, TGW hub/spoke, Tailscale ([ADR-008](docs/adrs/008-cilium-as-cross-cloud-cni.md)/[010](docs/adrs/010-private-eks-api-endpoint.md)/[017](docs/adrs/017-gateway-api-over-ingress.md)/[034](docs/adrs/034-transit-gateway-cross-account-connectivity.md)) |
| **Compute elasticity** | ✅ / ◐ | Karpenter node autoscaling (consolidation + spot + Graviton, BYOCNI-aware) on both clusters; HPA/KEDA workload autoscaling on the paved road next ([ADR-078](docs/adrs/078-cluster-elasticity-karpenter.md)) |
| **Observability** | ✅ | Full LGTM+profiles, multi-cluster, federated, zero-code (Beyla/Pyroscope), APM correlation, SLOs, synthetics, cost ([ADR-043](docs/adrs/043-self-hosted-observability-stack.md)/[077](docs/adrs/077-application-instrumentation-strategy.md)) |
| **Runtime threat detection** | ✅ preprod | Falco (eBPF) on the workload cluster ([ADR-045](docs/adrs/045-falco-runtime-threat-detection.md)) |
| **Cost visibility** | ✅ / ◐ | OpenCost in-cluster allocation + Grafana dashboard live; AWS CUR→Athena (true cloud spend by team) planned |
| **Day-2 operability** | ✅ | `platctl` — DAG-aware bootstrap / teardown / validate ([ADR-038](docs/adrs/038-platctl-cli-for-platform-operations.md)) |
| **Compliance tiers** | ◐ modeled | `compliance_tier` selects controls; SCPs mapped to SOC2/HIPAA/PCI/ISO/NIST/CIS. Clusters run `standard`; HIPAA/PCI selectable, not yet exercised ([ADR-013](docs/adrs/013-compliance-tier-model.md)) |
| **Per-team observability isolation** | ○ designed | Re-tenant every signal by team so devs see only their own telemetry ([#590](https://github.com/asanexample/platform/issues/590)) |
| **Self-service cloud resources** | ○ designed | S3/SQS/SNS/DynamoDB as governed Crossplane claims with derived least-privilege IAM ([ADR-073](docs/adrs/073-self-service-cloud-resources.md)) |
| **Agentic workloads** | ○ designed | Run/govern/secure AI agents as a first-class, safety-paramount capability ([ADR-074](docs/adrs/074-agentic-workloads-platform.md)/[075](docs/adrs/075-resource-agent.md)/[076](docs/adrs/076-agent-observability.md)) |
| **Multi-cloud** | ○ deferred | Cloud-agnostic layer ready; Azure/GCP after the AWS reference matures |

## Observability you'd actually want to operate

Self-hosted, multi-tenant, multi-cluster — the full **LGTM+profiles** stack, not just metrics
([ADR-043](docs/adrs/043-self-hosted-observability-stack.md)/[044](docs/adrs/044-mimir-durable-multi-tenant-metrics.md)/[077](docs/adrs/077-application-instrumentation-strategy.md)):

- **Every signal, every cluster, one pane.** Metrics (**Mimir**), logs (**Loki**), traces (**Tempo**), and
  continuous **CPU profiles** (**Pyroscope**) — all S3-backed, multi-tenant by `X-Scope-OrgID`, federated so a
  single Grafana spans the platform + preprod clusters, broken out by `cluster`.
- **Zero-code instrumentation.** **Beyla** (eBPF) gives RED metrics + distributed traces for every workload with
  no app changes; an Alloy eBPF agent profiles every process. New apps are observed the moment they run.
- **APM correlation.** Service graph + exemplars + Traces Drilldown, with one-click hops **trace → logs → flame
  graph** across the stack.
- **The measurement layer.** Error-budget **SLOs** (Sloth burn-rate alerts), **synthetics** (blackbox probes +
  k6 scripted checks), **cost visibility** (OpenCost), and curated alerting → Slack / PagerDuty / SNS.
- **Gated by SSO.** Grafana authenticates against **Keycloak** (OIDC), the platform's identity provider of record.

## What's actually running

Real, multi-account AWS infrastructure — production-shaped, deployed and operated via a purpose-built CLI.

**Platform account — shared-services cluster.** Private-API EKS (BYOCNI) with **Cilium 1.19.4**
(kube-proxy-replacement, Gateway API, Hubble); **ArgoCD** GitOps with **Keycloak OIDC** SSO + team-scoped RBAC;
**Backstage** developer portal ([ADR-051](docs/adrs/051-backstage-developer-portal.md)) on a CloudNative-PG
database; **Keycloak** as the app-facing IdP ([ADR-053](docs/adrs/053-identity-and-cross-system-authorization-strategy.md)/[059](docs/adrs/059-identity-topology-pluggable-idp-seam.md));
**Crossplane** environment control plane; **Kyverno** policy engine; the **observability hub**; **Transit
Gateway hub** + cross-VPC DNS; **Tailscale** for private access; self-hosted **GitHub Actions runners** (ARC)
for in-VPC CI.

**Preprod account — workload cluster.** EKS + Cilium + Gateway API; **environment isolation** via namespaces
(default-deny NetworkPolicies, quotas, per-team **Pod Identity**); ArgoCD Applications + per-team PR-preview
ApplicationSets; **Kyverno in Enforce** (pod hardening **and** supply-chain verification); **Falco** runtime
threat detection; cross-account ECR pull; Beyla instrumentation of the live workloads.

**Management account.** AWS Organizations + SCPs, IAM Identity Center (SSO), Terraform state (S3 + DynamoDB).
**Prod & Test accounts** round out the org (prod networking defined; test is the Terratest OIDC sandbox).

> **Day-2 first.** Everything is driven by **`platctl`**, a Go CLI that resolves the dependency DAG for
> bootstrap / teardown / validate ([ADR-038](docs/adrs/038-platctl-cli-for-platform-operations.md)). Private
> clusters are reached over Tailscale (split-DNS subnet routers) or SSM — the EKS API is private by design
> ([ADR-010](docs/adrs/010-private-eks-api-endpoint.md)).

## Using this as a reference

The infrastructure is the means; the **patterns, contracts, and decisions** are the deliverable.

- **Platform / DevEx engineers** adopting patterns — start with the [design docs](infra/docs/) (architecture,
  multi-tenancy, security, supply chain) and compose the [reusable modules](infra/modules/); `infra/live/` shows
  one opinionated composition.
- **Architects** evaluating an approach — the **88 [ADRs](docs/adrs/)** record *why* each choice was made, and
  what was rejected.
- **New team members** — the [Onboarding Guide](docs/onboarding.md) and the [Quick Start](#quick-start) below.

## The control plane: B·A·C·K on Kubernetes

Self-service runs on four planes, all reconciled continuously through the Kubernetes API:

| | Role | Status |
|---|------|--------|
| **B — [Backstage](https://backstage.io/)** | Developer portal — service catalog + software templates; the self-service front door that opens the gated PR creating the `XEnvironment` claim | **Live** ([ADR-051](docs/adrs/051-backstage-developer-portal.md)/[064](docs/adrs/064-backstage-provisioning-visibility.md)) |
| **A — ArgoCD** | GitOps reconciliation engine + per-team AppProjects/RBAC | **Live** ([ADR-021](docs/adrs/021-argocd-for-gitops.md)) |
| **C — [Crossplane](https://www.crossplane.io/)** | Infrastructure control plane — the environment footprint modeled as an XRD/Composition, **claimed through the K8s API** and continuously reconciled. The sole environment provisioner | **Live** ([ADR-046](docs/adrs/046-back-stack-for-developer-self-service.md)/[048](docs/adrs/048-federated-per-cluster-crossplane.md)) |
| **K — Kubernetes** | The universal control plane everything rides on | **Live** |

A developer picks a template → it scaffolds a repo and an `XEnvironment` claim → ArgoCD applies it → Crossplane
provisions the resources → Kubernetes runs them. Portal-driven, GitOps-reconciled, self-served, governed by
construction.

## Quick Start

```bash
# Prerequisites: the CLI toolchain pinned in /.tool-versions (OpenTofu, Terragrunt, kubectl, helm, AWS CLI v2).
# `mise install` (or asdf) installs the exact versions; CI and the self-hosted runner image read the same file.

# Authenticate (SSO via IAM Identity Center)
aws sso login --profile management

# Bootstrap the full platform stack (DAG-aware)
platctl bootstrap

# Or deploy a single unit
cd infra/live/aws/platform/us-east-1/platform/eks
AWS_PROFILE=management terragrunt apply

# Validate deployed infrastructure, then configure kubectl contexts
platctl validate
platctl kubeconfig
```

## Repository layout

```text
platform/
├── cmd/platctl/                 # Go CLI: DAG-aware bootstrap / teardown / validate / kubeconfig
├── gitops/                      # The source of truth: Team / Product / Environment / Release registries
├── docs/
│   ├── adrs/                    # 88 architecture decision records
│   ├── architecture/            # System design, supply chain, observability, environment model
│   ├── compliance/              # SCP → control mapping (SOC2/HIPAA/PCI/ISO/NIST/CIS)
│   ├── runbooks/                # Operational procedures
│   └── troubleshooting/         # Known issues and solutions
├── infra/
│   ├── live/aws/                # Terragrunt live configs — mgmt / platform / preprod / prod / test accounts
│   ├── modules/                 # ~67 reusable OpenTofu modules (cloud-agnostic + aws/ + cloudflare/)
│   ├── tests/                   # Terratest integration tests (Go)
│   └── root.hcl                 # Root Terragrunt config (S3 state, providers)
└── scripts/                     # Helper scripts (eks-tunnel, port-forwards, finalizer-clear)
```

## Modules

~67 reusable OpenTofu modules — a cloud-agnostic platform layer over per-cloud foundations. By domain:

- **Delivery & portal** — `argocd`, `argocd-apps`, `argocd-clusters`, `argo-rollouts` (progressive delivery,
  ADR-056), `backstage`, `github-teams`
- **Environment control plane** — `crossplane` (the `XEnvironment` XRD/Composition), `policy` (Kyverno),
  `cluster-rbac`, `gateway`, `gateway-config`
- **Identity & secrets** — `keycloak`, `keycloak-config`, `oauth2-proxy` (SSO front for no-native-auth UIs),
  `platform-directory` (workforce directory + owner-resolution, ADR-084), `external-secrets`, `secret-stores`,
  `cloudnative-pg`
- **Networking & access** — `cilium`, `cert-manager`, `external-dns`, `tailscale`, `tailscale-admin`
- **Security & on-call** — `policy` (Kyverno), `falco`, `pagerduty` (per-team on-call IaC, ADR-084), plus the
  SCP/IAM/supply-chain layers
- **Observability (17 modules)** — `observability` (kube-prometheus-stack) + the durable stores
  (`observability-mimir`/`-loki`/`-tempo`/`-pyroscope`), collectors (`-alloy`/`-beyla`/`-otel-collector`/
  `-otel-operator`/`-prometheus-agent`/`-pyroscope-ebpf`/`-events`), and the measurement layer
  (`-slo`/`-blackbox`/`-k6`/`-opencost`/`-cloudwatch-exporter`)
- **AWS foundation (22 modules)** — `organizations`, `networking`, `eks` (+ `eks-addons`/`-node-group`/
  `-pod-identity`), `karpenter` (node autoscaling, ADR-078), `transit-gateway`, `cross-vpc-dns`,
  `route53` (+ `-delegation`), `ecr`, `iam_roles`, `identity_center`, `github_oidc`, `cloudtrail`, `s3`,
  `sops-kms`, `ssm-bastion`, `sns-notifications`, `cost-allocation-tags`, `state_bootstrap`
- **Deferred** — `vcluster` (hard multi-tenancy, [ADR-033](docs/adrs/033-defer-vcluster-tenant-support.md))

Full catalog: [infra/modules/README.md](infra/modules/README.md).

## AWS accounts

Real account IDs live in `infra/live/aws/secrets.enc.yaml` (SOPS-encrypted, committed; KMS-decrypted at plan/apply, [ADR-066](docs/adrs/066-sops-encrypted-config-secrets.md); see `secrets.hcl.example` for the structure).

| Account | Purpose |
|---------|---------|
| **Management** | AWS Organizations, SCPs, IAM Identity Center (SSO), Terraform state (S3 + DynamoDB) |
| **Platform** | Shared services: EKS, ArgoCD, Backstage, Keycloak, Crossplane, TGW hub, ECR, the observability hub |
| **PreProd** | Workloads: EKS, environment namespaces, public ingress, Falco, TGW spoke |
| **Prod** | Production workloads (networking defined, not yet deployed) |
| **Test** | GitHub OIDC sandbox for Terratest CI (`PlatformDeployer`-managed) |

Cross-account access uses purpose-built IAM roles — **PlatformAdmin** (operate/debug, *not* author),
**PlatformDeployer** (Terragrunt apply), **DeveloperAccess-\<team\>** (namespace-scoped kubectl), and
**TerraformStateAccess**. `OrganizationAccountAccessRole` is break-glass only ([ADR-040](docs/adrs/040-platform-engineer-access-model.md)).

## Testing & CI

Tests use **Terratest (Go)** in `infra/tests/aws/<module>/` (plan-only where apply/destroy isn't CI-safe; the
OpenTofu binary is required — `TerraformBinary: "tofu"`).

```bash
cd infra/tests/aws/networking && go test -v -timeout 30m
```

CI (GitHub Actions, via OIDC — no stored credentials) runs OpenTofu/Terragrunt fmt + validate, TFLint, Kyverno
policy tests, and security scanning (Trivy IaC, Semgrep). Cluster-facing applies run on the in-VPC self-hosted
runners (ARC, [ADR-065](docs/adrs/065-self-hosted-github-actions-runners-arc.md)).

## Where it's heading

The foundation is established; the active frontiers:

- **Per-team observability isolation** — the single pane's access half: re-tenant every signal by team so
  developers see only their own telemetry across clusters ([#590](https://github.com/asanexample/platform/issues/590)).
- **Self-service cloud resources** — S3/SQS/SNS/DynamoDB as governed Crossplane claims with derived
  least-privilege IAM ([ADR-073](docs/adrs/073-self-service-cloud-resources.md)).
- **Agentic workloads** — running and governing AI agents as a first-class, safety-paramount platform capability
  ([ADR-074](docs/adrs/074-agentic-workloads-platform.md)/[075](docs/adrs/075-resource-agent.md)/[076](docs/adrs/076-agent-observability.md)).
- **Multi-cloud** — Azure/GCP foundations under the existing cloud-agnostic layer, once the AWS reference is mature.

## Documentation

| Document | Description |
|----------|-------------|
| [Documentation Index](docs/README.md) | Full doc map — start here |
| [Onboarding Guide](docs/onboarding.md) | New team member quickstart |
| [Crossplane Environment API](docs/architecture/crossplane-environment-api.md) | The `XEnvironment` claim → Composition model |
| [Supply-Chain Overview](docs/architecture/supply-chain-overview.md) | cosign + SBOM + SLSA L3 + Kyverno, end to end |
| [Observability Current State](docs/architecture/observability-current-state.md) | As-built LGTM+profiles, multi-cluster |
| [New Product / Deploy runbooks](docs/runbooks/) | The developer paved road, end to end |
| [Architecture Decisions](docs/adrs/) | **88 ADRs** documenting every significant choice |
