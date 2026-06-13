# Platform Capability Coverage

This platform is a **reference implementation** of an internal developer platform. This page maps it
against the **13 capability domains** in the
[CNCF Platforms White Paper](https://tag-app-delivery.cncf.io/whitepapers/platforms/) (CNCF TAG App
Delivery) — an honest, current snapshot of what's built, what's partial, and what's missing, with the
issue tracking each gap.

The CNCF whitepaper is a **developer-experience** lens. Several enterprise / non-functional capabilities it
under-probes — resilience, compliance *assurance*, safe delivery, zero-trust networking, and the multi-tenancy
model itself — are tracked in a [second axis below](#beyond-the-cncf-lens--enterprise-readiness), where the
live domain model (ADR-067/053) and surrounding ADRs (054–057) set direction.

**Legend:** ✅ Strong · 🟡 Partial · ❌ Missing · 📐 Designed (ADR accepted; not yet built)

## Scorecard

| # | CNCF capability | Status | What exists / gap | Tracking |
|---|-----------------|:------:|-------------------|----------|
| 8 | Infrastructure services | ✅ | EKS (BYOCNI/Cilium), VPC + Transit Gateway, node groups, EBS CSI storage | — |
| 11 | Identity & secret management | ✅ | AWS SSO/Identity Center, per-team IAM, **EKS Pod Identity** (ADR-041) + IRSA, external-secrets → Secrets Manager, cert-manager. *App-IdP + access-model-as-code designed (ADR-053).* | — |
| 12 | Security services | ✅ | Kyverno admission + RBAC/ABAC hardening, **cosign** sign/verify supply chain (ADR-014), SCPs, NetworkPolicies. *Depth gaps below; designed depth: east-west mTLS/zero-trust (ADR-057), continuous compliance assurance (ADR-055).* | [#108](https://github.com/asanexample/platform/issues/108) |
| 5 | Delivery & verification automation | ✅ | ArgoCD GitOps, ApplicationSet PR previews, cosign verifyImages, Kyverno admission gate. *Designed depth: progressive delivery — canary + auto-rollback (ADR-056).* | — |
| 4 | Build & test automation | ✅ | App CI (build/test/sign), the shift-left Kyverno gate (Phase 4), Terratest, platform CI | — |
| 13 | Artifact storage | 🟡 | ECR (per-team images) + GitHub (source). *Missing: generic package/binary + Helm chart registry* | — |
| 3 | Golden-path templates | 🟡 | Strong docs (ADRs, runbooks, CLAUDE.md authoring rules) + app-alpha reference app. *Missing: scaffolding ("create new app/environment")* | [#104](https://github.com/asanexample/platform/issues/104) |
| 2 | Self-service APIs/CLIs | 🟡 | `platctl` (ops); environments are a declarative Crossplane `XEnvironment` claim reconciled by a Composition (ADR-046/048). Self-service provisioning (form → gate → automerge → ArgoCD) is live (ADR-062), though still mediated by reviewed PRs rather than a fully unmediated developer API. Model: ADR-067 separates ownership/access/isolation/placement (Team → Product → Service → Environment), [domain API](platform-domain-api.md). | [#88](https://github.com/asanexample/platform/issues/88) |
| 7 | Observability | 🟡 | Metrics + curated dashboards + alerting **live** on the platform hub (kube-prometheus-stack + durable mimir/S3, ADR-043/044), Alertmanager→SNS, Hubble (network), **Falco** runtime threat detection on preprod (ADR-045), ArgoCD (deploy state). *Missing: logs/traces (Loki/Tempo, P3), cost, and spoke→hub remote-write rollout (P10). SLO/error-budget contract designed (ADR-054).* | [#102](https://github.com/asanexample/platform/issues/102) (+[#93](https://github.com/asanexample/platform/issues/93)) |
| 1 | Web portal / service catalog | ❌ | ArgoCD UI shows deploy state only; no developer portal / catalog | [#103](https://github.com/asanexample/platform/issues/103) |
| 9 | Data services | ❌ | Per-team **S3** shipped (#64); no DB/cache as a paved road. *Now reserved as the cloud-neutral `dataServices` dimension in the [domain API](platform-domain-api.md) (ADR-067) — direction set; build tracked by [#106].* | [#106](https://github.com/asanexample/platform/issues/106) |
| 10 | Messaging & event services | ❌ | None offered to environments | [#107](https://github.com/asanexample/platform/issues/107) |
| 6 | Development environments | ❌ | PR *preview* envs exist; no developer *dev* environments / hosted IDEs | [#105](https://github.com/asanexample/platform/issues/105) |

## The two strategic gaps

The platform has a **strong foundation** — infrastructure, identity, security/supply-chain, and GitOps
delivery are genuinely solid and several are reference-grade. The gaps cluster into two themes:

1. **The developer-experience / self-service layer** (the "Vercel-like" IDP goal): a **portal** (#1,
   [#103]), true **self-service** (#2, [#88]), **golden-path scaffolding** (#3, [#104]), and **dev
   environments** (#6, [#105]). Provisioning is now self-service via `XEnvironment` claims (ADR-062), but
   still routes through reviewed PRs rather than an unmediated developer API/portal. This is now the
   dominant gap.
2. **Observability** (#7, [#102]) — the foundation is now **live**: metrics, durable multi-tenant
   storage (mimir/S3), curated dashboards, and SNS alerting on the platform hub, plus Falco runtime
   detection. The remaining work is **logs/traces** (Loki/Tempo, P3), **cost** visibility, and fanning
   the spokes (preprod/prod) into the hub via authenticated remote-write (P10).

Secondary: **paved-road data & messaging services** (#9/#10, [#106]/[#107]) — extend the per-team
isolation pattern proven for S3 in #64. The earlier **security-depth** items (#12, [#108]) have largely
shipped — SBOM (cosign CycloneDX attest), **SLSA Build L3** (isolated provenance, ADR-042), runtime
detection (Falco, ADR-045), and SAST (Semgrep in CI) — leaving SCA/cost-of-ownership depth as the tail.

## Beyond the CNCF lens — enterprise readiness

The 13 CNCF domains measure the *developer-experience* surface. Enterprise operation adds a **non-functional
axis** the whitepaper barely touches — can it survive a region loss, *prove* its controls to an auditor, ship
to regulated prod safely, and isolate services cryptographically? The **multi-tenancy model** itself is now
**live** (ADR-067: Team → Product → Service → Environment, separating ownership from access from isolation from
placement); the remaining rows are **designed** as strategy/direction ADRs — *named and routed, not yet built.*

| Capability | Status | Direction / what exists today | ADR |
|------------|:------:|-------------------------------|-----|
| Multi-tenancy model (ownership · access · isolation · placement) | ✅ | Team → Product → Service → Environment, live on Crossplane (`XEnvironment`), with reserved enterprise dimensions (tier, residency, isolation dial, customer, lifecycle) | [067](../adrs/067-idp-domain-model.md) · [schema](platform-domain-api.md) |
| Cross-system identity & authz | 📐 | Keycloak app-IdP brokering to Identity Center + access-model-as-code; today AWS SSO + Dex | [053](../adrs/053-identity-and-cross-system-authorization-strategy.md) |
| Resilience & business continuity | 📐 | Per-tier recovery/availability postures, backup/DR, cross-region state, single-region control plane w/ tested restore; **nothing built yet** | [054](../adrs/054-platform-resilience-and-business-continuity.md) |
| Compliance assurance & evidence | 📐 | Control-catalog-as-code → SOC2/PCI/HIPAA, continuous scanning, retention-locked per-environment evidence; controls exist, *assurance* doesn't | [055](../adrs/055-compliance-assurance-and-continuous-control-evidence.md) |
| Progressive delivery & safe rollback | 📐 | Argo Rollouts canary + metric gates, tier-keyed strategy, regulated approval gate; today plain ArgoCD sync | [056](../adrs/056-progressive-delivery-and-safe-rollback.md) |
| Service identity & east-west zero trust | 📐 | Cilium transparent encryption + mTLS, SPIFFE workload identity; today L3/L4 NetworkPolicy only | [057](../adrs/057-service-identity-and-east-west-zero-trust.md) |

> **📐 Designed ≠ built.** Each 📐 row is a strategy/direction ADR not yet implemented. The value
> today is that the gaps are *named and routed*, not that they're closed.

## Notes

- "Strong" reflects *that the capability exists and is multi-tenant-isolated*, not that it is exhaustive.
- The CNCF scorecard reflects **built** status; the enterprise-readiness axis uses 📐 for **designed** (ADR
  accepted, implementation pending) — don't read a 📐 as shipped.
- The per-environment isolation pattern (declare in the `XEnvironment` claim → Crossplane Composition → EKS
  Pod Identity, default-deny by construction — see
  [ADR-041](../adrs/041-pod-identity-for-tenant-workloads.md)) is the intended template for the missing
  data/messaging paved roads (#106/#107).
- This page should be updated as gaps close; treat the linked issues as the backlog.

[#88]: https://github.com/asanexample/platform/issues/88
[#102]: https://github.com/asanexample/platform/issues/102
[#103]: https://github.com/asanexample/platform/issues/103
[#104]: https://github.com/asanexample/platform/issues/104
[#105]: https://github.com/asanexample/platform/issues/105
[#106]: https://github.com/asanexample/platform/issues/106
[#107]: https://github.com/asanexample/platform/issues/107
[#108]: https://github.com/asanexample/platform/issues/108
