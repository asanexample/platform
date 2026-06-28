# ADR-046: Adopt the BACK Stack for Developer Self-Service

**Date:** 2026-06-02

**Status:** Accepted — **implemented (P1–P3, #174).** Tenant provisioning is now Crossplane `Tenant` claims:
both teams (alpha, bravo) are migrated and provisioned by the Composition; the `infra/modules/tenant` module
and the preprod `tenants`/`pod-identity` units and the platform `s3-shared` unit are **retired** (deleted), and
the per-team role/access-entry loops were removed from the `iam-roles` and `eks` units. Establishes the target
architecture for developer self-service now that the platform foundation is in place. Builds on GitOps
([ADR-021](021-argocd-for-gitops.md)), the tenant model
([ADR-027](027-hybrid-tenant-isolation-model.md)/[031](031-multi-app-tenant-model.md)), Pod Identity
([ADR-041](041-pod-identity-for-tenant-workloads.md)), and policy-as-code ([ADR-014](014-kyverno-as-policy-engine.md)).

> **Vocabulary superseded by [ADR-067](067-idp-domain-model.md):** "Tenant"/`Tenant` claim → **Environment**/`XEnvironment` (Team→Product→Service; the intermediate `XTenant` was also removed); `teams.hcl` → the git-native `Team` + `Product` registries. The decision/topology below is unchanged — read the tenant vocabulary as the v2 naming.

## Context

The platform's goal is a Vercel-like developer experience: product teams self-serve onto a governed, secure,
compliant substrate. The foundation for that now exists — multi-account AWS, private EKS, GitOps delivery,
admission policy, a signed supply chain, and self-hosted observability.

Tenant **self-service today is a declarative contract**: a team's identity, apps, route hostnames, and AWS
access are declared in `teams.hcl`, and the `tenant` module + the per-team `policy`/ECR/Pod-Identity wiring
provision the rest. This was the right first step — the **thinnest viable platform** that proves the tenancy,
isolation, and supply-chain model. But it is **platform-team-mediated, not developer self-service**:

- A platform engineer edits `teams.hcl` and runs Terragrunt; there is **no developer-facing portal**.
- Provisioning is **point-in-time `terragrunt apply`**, not continuous reconciliation — no drift correction.
- Onboarding a team or app is a human, HCL-editing step, not a self-service action with guardrails.

To reach true self-service we need a **developer portal** and a **Kubernetes-native infrastructure control
plane** — provisioning exposed as APIs that teams *claim*, reconciled continuously.

## Alternatives considered

**1. The BACK stack — Backstage + ArgoCD + Crossplane + Kubernetes (chosen).** The de-facto open-source
platform-engineering reference. **Backstage** (CNCF, the standard Internal Developer Portal) is the
self-service front door — catalog, software templates (Scaffolder), TechDocs. **ArgoCD** (already in place,
ADR-021) is the GitOps delivery engine. **Crossplane** (CNCF) is the infrastructure control plane: it exposes
provisioning through the Kubernetes API and composes low-level resources into opinionated platform APIs
(`CompositeResourceDefinition`s + `Composition`s) that teams **claim** — continuously reconciled, with drift
correction. **Kubernetes** is the universal control plane it all rides on. OSS-default, own-your-control-plane,
and a direct fit for the existing K8s/GitOps/policy stack.

**2. Stay with `teams.hcl` + Terragrunt (rejected).** Zero new moving parts, but it is the status quo — no
portal, platform-team-mediated, point-in-time. It cannot deliver developer self-service; it is the interim
this ADR supersedes for tenant-facing provisioning.

**3. Backstage portal over Terragrunt, no Crossplane (rejected).** A portal that triggers pipelines/PRs to run
Terragrunt. Gives a DX front-end but keeps provisioning **imperative and point-in-time** — no continuous
reconciliation, no drift correction, a brittle portal↔CI↔Terraform chain. The **"C" is the point**: a
declarative, K8s-native control plane is what makes self-service safe and self-healing.

**4. A Terraform-based control plane (Terraform Operator / Atlas) instead of Crossplane (rejected/close).**
Keeps the existing Terraform/OpenTofu investment and runs it reconciliation-style. But it wraps imperative
Terraform runs rather than offering Crossplane's first-class **composition** model and provider ecosystem; the
claim/XRD UX and per-resource reconciliation are a stronger fit for exposing opinionated self-service APIs.
Foundational infra stays on Terragrunt regardless (below), so this would add a second Terraform runner without
the composition benefits.

**5. A SaaS IDP (Port, Humanitec, etc.) (rejected).** Faster to a polished portal, but proprietary, less
control over the control plane, and counter to the OSS-default, reference-architecture intent of this repo —
the goal is to *demonstrate* the open patterns, not outsource them.

**6. A different portal than Backstage (rejected).** Backstage has the largest plugin ecosystem (ArgoCD,
Kubernetes, TechDocs, Crossplane) and is the CNCF reference; no compelling reason to diverge.

## Decision

Adopt the **BACK stack** as the target architecture for developer self-service, with this division of
responsibility:

- **Crossplane = the tenant control plane.** Model **tenant-facing** capabilities — namespace +
  ResourceQuota/LimitRange/default-deny NetworkPolicy + CiliumNetworkPolicies, ECR repo, IAM/EKS Pod Identity,
  per-team Kyverno policy, and route-hostname allow-list — as a **`Tenant` (X)RD + Composition** that a team
  *claims*. This is a near 1:1 replacement of the `tenant` module + the per-team `teams.hcl` wiring, reconciled
  continuously.
- **Supply-chain split.** The Composition provisions only the **per-tenant guardrails** — the Kyverno
  `restrict-images` (per-team ECR registry scoping) and `restrict-route-hostnames` (per-team Gateway hostname
  allow-list) ClusterPolicies. The **platform-owned supply-chain verification** — cosign keyless
  `verify-images` and SLSA `verify-attestations` ([ADR-042](042-isolated-build-provenance-slsa-l3.md)) — stays
  in the `policy` unit/module (ADR-014), deployed for **all** teams (including migrated ones), not in the
  Composition. `teams.hcl` therefore still feeds app delivery (argocd-apps) and these platform-owned
  supply-chain policies; migrated teams carry `migrated = true`.
- **Claim delivery.** Tenant claims are authored in the **`tenant-claims` Terragrunt unit** (a
  platform-controlled path) and reconciled by the per-cluster Composition (per [ADR-048](048-federated-per-cluster-crossplane.md));
  Backstage (P5) later scaffolds claims into that same path. A single `Tenant` claim (kind `XTenant`,
  `apiVersion platform.refplat.org/v1alpha1`) renders the full tenant footprint: namespace + RBAC +
  ResourceQuota/LimitRange + NetworkPolicies/CiliumNetworkPolicies; per-team `restrict-images` /
  `restrict-route-hostnames`; the `Pod-team-<team>` IAM role + EKS Pod Identity association; the
  `DeveloperAccess-<team>` IAM role + EKS access entry → `team-<team>:developers`; and the cross-account ECR
  repo.
- **Foundational infra stays on Terragrunt.** Organizations/SCPs, accounts, networking, EKS, node groups, and
  state are **not** moved to Crossplane: they bootstrap the very cluster Crossplane runs on, change rarely, and
  are operator-, not developer-, facing. OpenTofu + Terragrunt remains the foundation layer; Crossplane is the
  tenant/app layer on top.
- **Crossplane runs on each workload cluster (federated), Backstage on the platform cluster**, delivered as
  **Terragrunt Helm add-on units** like every other platform service (Kyverno, cert-manager, Cilium, ArgoCD
  itself) — platform components stay on Terragrunt; **ArgoCD delivers tenant/app workloads and the tenant
  claims/XRs**, not the platform add-ons. **IAM Identity Center SSO** for Backstage (consistent with ArgoCD
  and Grafana). *(Topology updated by [ADR-048](048-federated-per-cluster-crossplane.md): Crossplane is
  per-cluster — each workload cluster provisions its own tenants locally — rather than a single hub on the
  platform cluster reaching across clusters. The platform cluster keeps its Crossplane as a standard add-on.)*
  Whether Crossplane should later self-manage via ArgoCD is a future call, not a P1 decision.
- **The golden path is preserved**: a Backstage Software Template scaffolds an app repo + a Crossplane Claim +
  an ArgoCD Application; the existing supply-chain verification, admission policy, and observability apply
  unchanged. Backstage is a *thin portal over real, reconciled APIs* — which is why the control plane comes
  first.

### Staged rollout (control-plane first)

The portal is only as good as the APIs it exposes, so Crossplane lands before Backstage:

- **Phase 0 — foundation (done):** multi-account AWS, EKS, GitOps, policy-as-code, signed supply chain,
  observability; `teams.hcl` as the interim tenant contract.
- **Phase 1 — Crossplane core:** install Crossplane v2 on the platform cluster (a Terragrunt Helm add-on unit)
  with the Upbound AWS provider family; a least-privilege provisioning identity authenticated via EKS Pod
  Identity (ADR-041), scoped to tenant resources (its own privileged control-plane role). Started ECR-only,
  extended to IAM + Pod Identity associations as the Tenant Composition (P2) needs them.
- **Phase 2 — the `Tenant` XRD/Composition:** model the tenant capabilities as a Composition; prove a `Tenant`
  claim reconciles to the **same** resources the `tenant` module produces today (parity test). Authored against
  the **Crossplane v2** API model — composite resources are **namespaced** and the legacy cluster-scoped Claim
  type is deprecated, so a "claim" here is a namespaced `Tenant` XR; Compositions are function-based pipelines.
- **Phase 3 — migrate tenants (coexistence):** cut one team (alpha) to a `Tenant` claim, validate parity, then
  migrate the rest team-by-team. `teams.hcl` stays authoritative per team until that team is cut over; retire
  the `tenant` module's tenant provisioning once all teams are migrated.
- **Phase 4 — Backstage:** deploy Backstage (ArgoCD + IC SSO); software catalog + TechDocs (ingest the
  `infra/docs` set and service metadata).
- **Phase 5 — Software Templates:** Scaffolder templates for tenant/app onboarding → repo + Crossplane claim +
  Argo App, replacing hand-edited `teams.hcl` onboarding with portal-driven self-service.
- **Phase 6 — plugins / close the loop:** Backstage plugins for ArgoCD (deploy status), Crossplane (claim
  status), Kyverno (policy reports), and Grafana (per-service dashboards).

## Consequences

**Positive.** True developer self-service with a portal; provisioning becomes declarative, K8s-native, and
**continuously reconciled** (drift correction the current `terragrunt apply` model lacks); platform-team toil
drops; the tenant model is exposed as a versioned, composable API; the stack composes onto — rather than
replaces — the existing GitOps/policy/supply-chain/observability investment.

**Negative / risks.**

- **Operational complexity + a new control plane to run and secure.** Crossplane's provisioning identity is
  broadly privileged (it creates IAM, ECR, etc.) — it must be tightly scoped and is a high-value target;
  treat it like the deployer role. Crossplane has a real learning curve.
- **Two provisioning models during migration** (Terragrunt for foundation + the in-flight tenant migration);
  the coexistence window needs care so a team isn't half in each.
- **Mapping the nuanced tenant model to a Composition** is non-trivial — Pod Identity associations, per-team
  Kyverno policies + hostname allow-lists, and cross-account ECR all have to compose correctly; the Phase 2
  parity test is the gate.
- **Backstage is a product to own** (upgrades, plugins, catalog hygiene).

These are the substance of the implementation epic; the parity test (Phase 2) and the scoped Crossplane
identity are the two highest-risk items to get right first.
