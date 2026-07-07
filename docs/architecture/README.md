# Architecture Index

The *how it works* and *where we're going* explainers for this platform, grouped by
domain. These describe the as-built (and forward-looking) architecture; the operational
*how-to* lives in [`../runbooks/`](../runbooks/README.md) and the *why* in
[`../adrs/`](../adrs/README.md).

## Identity & access

| Document | Summary |
|----------|---------|
| [Identity & SSO](identity-and-sso.md) | Where we are: how a human signs into the platform's apps (ArgoCD, Backstage, Grafana) via Keycloak OIDC, where permissions come from, the pluggable seam |
| [Identity & Access Strategy](identity-and-access-strategy.md) | **North Star** — the forward-looking direction (workforce-first, decide→derive→project) companion to identity-and-sso |
| [PagerDuty Identity Handoff](pagerduty-identity-handoff.md) | How the IaC-provisioned `pagerduty` on-call structure connects to people owned by the identity workstream |
| [Temporary-Power Activation Controller](temporary-power-activation-controller.md) | Design for the always-on JIT-elevation controller that grants a dangerous power for a bounded window (ADR-088) |

## Delivery & supply chain

| Document | Summary |
|----------|---------|
| [Delivery Pipeline](delivery-pipeline.md) | The end-to-end spine tying the subsystems together: scaffold → registry/Composition → supply chain → delivery → gated prod |
| [Promotion & Release](promotion-and-release.md) | Promote-by-digest up the stage ladder, the release-keyed ApplicationSet, auto ≤ staging, gated prod |
| [Zero-Downtime Deployments](zero-downtime-deployments.md) | How deploys avoid dropping traffic + canary/blue-green with auto-rollback (ADR-085 architecture reference) |
| [Supply-Chain Overview](supply-chain-overview.md) | The map: SBOM, cosign signatures, SLSA provenance, Rekor, Kyverno verify, the SLSA Build L3 matrix |
| [Cosign Image Signing](cosign-image-signing.md) | From-scratch explainer: keyless signing, Fulcio/Rekor, per-team identity, Kyverno verify |

## Tenancy & domain model

| Document | Summary |
|----------|---------|
| [Platform Domain API](platform-domain-api.md) | **Normative** Team / Product / Service / Environment / Customer schemas (ADR-067 contract, v1beta1) |
| [Crossplane Environment API](crossplane-environment-api.md) | How environments are provisioned: the `XEnvironment` claim contract and what the Composition reconciles |
| [Crossplane Composition Authoring](crossplane-composition-authoring.md) | The *how* behind the Environment API — extending the XRD, Pipeline functions, the status-loop pattern |
| [Preprod Environment Model](preprod-environment-model.md) | Namespace-based environment isolation architecture (ADR-027/033) |
| [Kyverno Policy Catalog](kyverno-policy-catalog.md) | The authoritative list of admission policies enforced per cluster, what they check, and their scope |
| [Kyverno Shift-Left](kyverno-shift-left.md) | Pre-merge (CI) policy validation that mirrors admission so violations fail before they reach the cluster |
| [Tenant API v2](tenant-api-v2.md) | ⚠️ **Historical / superseded** by [platform-domain-api.md](platform-domain-api.md) — the pre-ADR-067 Team/Tenant/Zone/Customer model |

## Observability

| Document | Summary |
|----------|---------|
| [Observability — Current State](observability-current-state.md) | What is actually deployed today (LGTM+P hub + Mimir): topology, multi-tenancy/security model, storage |

## Networking & gateway

| Document | Summary |
|----------|---------|
| [Gateway & Ingress](gateway-and-ingress.md) | How an external request reaches an environment pod: shared Cilium Gateway → NLB → cert-manager → external-dns (ADR-060/061) |
| [East-West Zero Trust](east-west-zero-trust.md) | How service-to-service traffic is secured: Cilium WireGuard encryption + mutual auth with SPIFFE/SPIRE workload identity, the auth-required policy, and the alpha-shop↔alpha-checkout demo (ADR-057) |
| [Secrets & External Secrets](secrets-and-external-secrets.md) | How a Secrets Manager secret reaches a pod via ESO with no long-lived cluster credential |

## Foundation

| Document | Summary |
|----------|---------|
| [AWS Organizations](aws-organizations.md) | OU hierarchy, SCP catalog, exempt roles, and the org security model |
| [Config Hierarchy](config-hierarchy.md) | How the six-layer Terragrunt configuration composes values, pins module sources, and wires remote state |
| [Platform Capability Coverage](platform-capability-coverage.md) | This reference platform mapped against the 13 IDP capability domains |
