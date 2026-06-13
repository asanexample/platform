# Documentation Index

This repository manages infrastructure with OpenTofu modules orchestrated by
Terragrunt. It is **multi-cloud by design; AWS is the only cloud deployed** — only
`live/aws/` exists. The shared modules are written cloud-agnostically and the layout
is parameterized for Azure/GCP, but those are **designed-for, not built** (no
`live/azure/` or `live/gcp/`) and not planned for 2026. All cloud resources are
defined declaratively, version-controlled, and deployed through a layered
configuration hierarchy that promotes consistency across environments.

> **Current identity state:** **Keycloak** is the app-facing IdP of record (ArgoCD
> direct; Backstage via oauth2-proxy). Dex is legacy. See
> [Identity & SSO](architecture/identity-and-sso.md).

## Start Here

| Document | Description |
|----------|-------------|
| [Onboarding Guide](onboarding.md) | New team member quickstart: prerequisites, first deploy, daily workflows |
| [User Guide](user-guide.md) | Complete reference for module configuration, deployments, and day-2 operations |
| [Glossary](glossary.md) | Platform-specific terms (environment, the seam, generated host, Pod Identity, …) defined in one place |

## How It Works

| Document | Description |
|----------|-------------|
| [Architecture](architecture/) | System design, network topology, and multi-cloud strategy |
| [Identity & SSO](architecture/identity-and-sso.md) | How login works: Keycloak (IdP of record), oauth2-proxy, the access model, the pluggable seam |
| [Gateway & Ingress](architecture/gateway-and-ingress.md) | Cilium Gateway → NLB → cert-manager → external-dns → Kyverno hostname guard (ADR-060/061) |
| [Secrets & External Secrets](architecture/secrets-and-external-secrets.md) | Secrets Manager → ESO ClusterSecretStore → ExternalSecret → k8s Secret; platform vs environment |
| [Platform Domain API](architecture/platform-domain-api.md) | **Normative schema** for the ADR-067 domain model — Team / Product / Service / Environment / Customer (v1alpha3; supersedes the ADR-049 tenant-api-v2) |
| [Crossplane Composition Authoring](architecture/crossplane-composition-authoring.md) | The *how* behind the Environment API: XRD, Pipeline functions, the status-loop pattern |
| [Supply-Chain Overview](architecture/supply-chain-overview.md) | Why + end-to-end flow: SBOM, cosign, SLSA provenance, Rekor, Kyverno, and the SLSA Build L3 matrix |
| [Observability Current State](architecture/observability-current-state.md) | As-built P1 hub + P2 mimir: topology, multi-tenancy/security model, storage |
| [Preprod Environment Model](architecture/preprod-environment-model.md) | Namespace-based environment isolation architecture |
| [Cosign Image Signing](architecture/cosign-image-signing.md) | From-scratch explainer: keyless signing, Fulcio/Rekor, per-team identity, Kyverno verify |
| [Kyverno Policy Catalog](architecture/kyverno-policy-catalog.md) | Every admission policy enforced per cluster, scope, and mode |
| [AWS Organizations](architecture/aws-organizations.md) | OU hierarchy, SCP catalog, exempt roles, blast-radius analysis |
| [Platform Capability Coverage](architecture/platform-capability-coverage.md) | The platform mapped against the CNCF IDP capability domains |
| [Config Hierarchy](architecture/config-hierarchy.md) | Six-layer Terragrunt configuration precedence (root through unit) |
| [Module Design](../infra/docs/13-module-design.md) | Conventions for writing and consuming infrastructure modules |

## How-To Guides

| Document | Description |
|----------|-------------|
| [Runbooks](runbooks/) | Step-by-step operational procedures for common tasks |
| [Deploy App to Preprod](runbooks/deploy-app-preprod.md) | Developer guide: repo structure, manifests, ECR push, ArgoCD sync |
| [Environment Onboarding](runbooks/environment-onboarding.md) | Platform team: onboard/offboard teams, choose isolation mode |
| [App Supply-Chain Onboarding](runbooks/app-supply-chain-onboarding.md) | App team: wire cosign signing + SBOM + SLSA provenance into CI |
| [Supply-Chain Incidents](runbooks/supply-chain-incidents.md) | Verification failures, Sigstore outage, identity rotation, break-glass |
| [Observability Access](runbooks/observability-access.md) | Access Grafana (Tailscale + creds), dashboards, query mimir, alerting |
| [Observability Troubleshooting](runbooks/observability-troubleshooting.md) | Grafana/Prometheus/mimir/storage diagnostics + apply gotchas |
| [EKS Cluster Access](runbooks/eks-cluster-access.md) | kubectl setup for platform engineers and developers |
| [SSO Troubleshooting](runbooks/identity-sso-troubleshooting.md) | "Can't log in / no permissions" master triage across ArgoCD, Backstage, Keycloak |
| [Debug Ingress & DNS](runbooks/debug-ingress-and-dns.md) | App unreachable / TLS fails / hostname rejected — external-dns, cert-manager, HTTPRoute, Kyverno |
| [Debug ArgoCD Sync](runbooks/debug-argocd-sync.md) | OutOfSync/Unknown, cross-account reachability, ApplicationSet PR-preview failures |
| [ArgoCD SSO](runbooks/argocd-sso.md) | ⚠️ legacy (embedded Dex); current model is Keycloak — see Identity & SSO |
| [Transit Gateway Operations](runbooks/transit-gateway-operations.md) | Hub/spoke TGW: add spokes, verify connectivity, troubleshoot |
| [Upgrade Procedures](runbooks/upgrade-procedures.md) | EKS, Cilium, Helm chart, and toolchain version upgrades |
| [User Guide](user-guide.md) | Greenfield and brownfield deployments, day-2 operations |
| [Troubleshooting](troubleshooting/) | Solutions to known issues and error patterns |

## Why (Decisions)

| Document | Description |
|----------|-------------|
| [ADR Index](adrs/README.md) | **Canonical, complete list of all Architecture Decision Records** (grouped by domain, with status) |
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
infra/modules/      Reusable OpenTofu modules (aws/ + shared; azure/, gcp/ scaffolded, not built)
infra/live/aws/     Terragrunt live configurations per env/region/workload (AWS only today)
infra/tests/        Terratest (Go) module integration tests
infra/docs/         Infrastructure design documentation (numbered series)
infra/scripts/      Helper scripts and Terragrunt hooks
cmd/platctl/        platctl orchestration CLI (Go, ADR-038)
```
