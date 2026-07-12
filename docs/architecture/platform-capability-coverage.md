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

*Last reviewed: 2026-06-28.*

## Scorecard

| # | CNCF capability | Status | What exists / gap | Tracking |
|---|-----------------|:------:|-------------------|----------|
| 8 | Infrastructure services | ✅ | EKS (BYOCNI/Cilium), VPC + Transit Gateway, EBS CSI storage. **Compute elasticity:** Karpenter node autoscaling (just-in-time provisioning + consolidation, spot + Graviton) on **both** clusters — the static spot workload node group is retired; a fixed on-demand system group remains (ADR-078). *HPA/KEDA workload autoscaling is the next paved-road step.* | — |
| 11 | Identity & secret management | ✅ | **Keycloak OIDC** as the app IdP of record (ArgoCD, Backstage, Grafana sign-in; pluggable-IdP seam, ADR-053/059), AWS SSO/Identity Center for console/CLI, per-team IAM, **EKS Pod Identity** (ADR-041/047 — the platform standard; IRSA remains only for the EBS CSI managed add-on), external-secrets → Secrets Manager, cert-manager. | — |
| 12 | Security services | ✅ | Kyverno admission + RBAC/ABAC hardening, **cosign** sign/verify supply chain (ADR-014/050), SLSA Build L3 (ADR-042), SCPs, NetworkPolicies. *Designed depth: east-west mTLS/zero-trust (ADR-057), continuous compliance assurance (ADR-055).* | [#108](https://github.com/asanexample/platform/issues/108) |
| 5 | Delivery & verification automation | ✅ | ArgoCD GitOps, ApplicationSet PR previews, signed-digest promotion ladder (dev→test→staging→prod, gated prod + SoD, ADR-071), cosign verifyImages, Kyverno admission gate. *Designed depth: progressive delivery — canary + auto-rollback (ADR-056).* | — |
| 4 | Build & test automation | ✅ | App CI (shared `build-sign.yml`: build/test/sign/SBOM/SLSA, ADR-050), the **gitops Gate** envelope shift-left (#388), Terratest, platform CI | — |
| 13 | Artifact storage | 🟡 | ECR (per-team images) + GitHub (source). *Missing: generic package/binary + Helm chart registry* | — |
| 3 | Golden-path templates | ✅ | **Backstage software templates** (New Product, Request Promotion, Deprovision Product/Environment, New Resource) scaffold a repo + `XEnvironment` claim via a gated PR; thin-caller CI + `k8s/` overlays; ADRs/runbooks/CLAUDE.md authoring rules (ADR-051/071). | [#104](https://github.com/asanexample/platform/issues/104) |
| 2 | Self-service APIs/CLIs | 🟡 | `platctl` (ops) + the **Backstage portal** front door; environments are a declarative Crossplane `XEnvironment` claim reconciled by a Composition (ADR-046/048). Self-service provisioning (form → gitops Gate → automerge → ArgoCD) is live (ADR-062), though still mediated by reviewed PRs rather than a fully unmediated developer API. Model: ADR-067 separates ownership/access/isolation/placement (Team → Product → Service → Environment), [domain API](platform-domain-api.md). | [#88](https://github.com/asanexample/platform/issues/88) |
| 7 | Observability | ✅ | Full **LGTM+Profiles** live: metrics (Prometheus + durable Mimir/S3), logs (Loki + Alloy), traces (Tempo + OTel), profiles (Pyroscope), zero-code instrumentation (Beyla eBPF), APM/RED correlation, SLOs (Sloth), synthetics, OpenCost allocation — **multi-cluster, federated** (preprod spoke remote-writes all three signals), Grafana **Keycloak SSO**, Alertmanager→SNS/Slack/PagerDuty, plus **Falco** runtime detection on preprod (ADR-043/044/045/077). *Per-team: real write-split + soft read scoping (the hard read-proxy was built then retired, #1269); CUR true-spend shipped (#668).* | [#102](https://github.com/asanexample/platform/issues/102) ([#590](https://github.com/asanexample/platform/issues/590)) |
| 1 | Web portal / service catalog | ✅ | **Backstage** developer portal (CNPG-backed, Keycloak OIDC sign-in) — Team/Product/Environment catalog, software templates, and provisioning visibility (ArgoCD/K8s tabs) (ADR-051/064). | [#103](https://github.com/asanexample/platform/issues/103) |
| 9 | Data services | 🟡 | Per-team **S3** shipped (#64); **self-service cloud resources** (S3/SQS/SNS/DynamoDB via curated Crossplane Compositions + derived least-privilege IAM, governed by the Team envelope) accepted and in progress (ADR-073). DB/cache as a paved road still pending. | [#106](https://github.com/asanexample/platform/issues/106) |
| 10 | Messaging & event services | 🟡 | SQS/SNS are in scope of the self-service resource catalog (ADR-073, in progress); not yet offered to environments. | [#107](https://github.com/asanexample/platform/issues/107) |
| 6 | Development environments | ❌ | PR *preview* envs exist; no developer *dev* environments / hosted IDEs | [#105](https://github.com/asanexample/platform/issues/105) |

## The remaining gaps

The platform has a **strong foundation** — infrastructure (now with Karpenter elasticity), identity,
security/supply-chain, GitOps delivery, the **Backstage portal + scaffolding**, and **full LGTM+Profiles
observability** are genuinely solid and several are reference-grade. The two themes that were the dominant
gaps have largely closed; what remains:

1. **The developer-experience / self-service layer** (the "Vercel-like" IDP goal) is now mostly **live**:
   the **portal** (#1, [#103]) and **golden-path scaffolding** (#3, [#104]) ship via Backstage, and
   provisioning is self-service via `XEnvironment` claims (ADR-062). The residual self-service gap (#2,
   [#88]) is that provisioning still routes through reviewed PRs rather than an unmediated developer API,
   and there are still **no developer dev environments / hosted IDEs** (#6, [#105]).
2. **Observability** (#7, [#102]) — now **live** end-to-end: LGTM+Profiles (metrics/logs/traces/profiles),
   zero-code instrumentation (Beyla), APM correlation, SLOs, synthetics, and OpenCost allocation, all
   **multi-cluster and federated** (preprod spoke), with Grafana Keycloak SSO. Per-team isolation ([#590])
   landed as a real **write-split** plus **soft** read scoping — the hard fail-closed read-proxy was built then
   **retired** (#1269) as unreliable in OSS Grafana; AWS CUR true-spend shipped (#668).

Secondary: **paved-road data & messaging services** (#9/#10, [#106]/[#107]) — the per-team isolation
pattern proven for S3 in #64 is being generalized into a **self-service resource catalog** (S3/SQS/SNS/
DynamoDB via curated Crossplane Compositions + derived least-privilege IAM, ADR-073, in progress). The
**security-depth** items (#12, [#108]) have largely shipped — SBOM (cosign CycloneDX attest), **SLSA Build
L3** (isolated provenance, ADR-042), runtime detection (Falco, ADR-045), SAST (Semgrep in CI), and
**secret scanning** (gitleaks in CI over full history + pre-commit, #1148) — leaving SCA/cost-of-ownership
depth as the tail.

## Beyond the CNCF lens — enterprise readiness

The 13 CNCF domains measure the *developer-experience* surface. Enterprise operation adds a **non-functional
axis** the whitepaper barely touches — can it survive a region loss, *prove* its controls to an auditor, ship
to regulated prod safely, and isolate services cryptographically? The **multi-tenancy model** itself is now
**live** (ADR-067: Team → Product → Service → Environment, separating ownership from access from isolation from
placement); the remaining rows are **designed** as strategy/direction ADRs — *named and routed, not yet built.*

| Capability | Status | Direction / what exists today | ADR |
|------------|:------:|-------------------------------|-----|
| Multi-tenancy model (ownership · access · isolation · placement) | ✅ | Team → Product → Service → Environment, live on Crossplane (`XEnvironment`), with reserved enterprise dimensions (tier, residency, isolation dial, customer, lifecycle) | [067](../adrs/067-idp-domain-model.md) · [schema](platform-domain-api.md) |
| Cross-system identity & authz | 🟡 | **Keycloak OIDC is live** as the app IdP of record (ArgoCD, Backstage, Grafana; pluggable-IdP seam, ADR-059) alongside AWS SSO for console/CLI; the full access-model-as-code brokering remains the design target | [053](../adrs/053-identity-and-cross-system-authorization-strategy.md) · [059](../adrs/059-identity-topology-pluggable-idp-seam.md) |
| Resilience & business continuity | 📐 | Per-tier recovery/availability postures, backup/DR, cross-region state, single-region control plane w/ tested restore; **nothing built yet** | [054](../adrs/054-platform-resilience-and-business-continuity.md) |
| Compliance assurance & evidence | 📐 | Control-catalog-as-code → SOC2/PCI/HIPAA, continuous scanning, retention-locked per-environment evidence; controls exist, *assurance* doesn't | [055](../adrs/055-compliance-assurance-and-continuous-control-evidence.md) |
| Progressive delivery & safe rollback | 📐 | Argo Rollouts canary + metric gates, tier-keyed strategy, regulated approval gate; today plain ArgoCD sync | [056](../adrs/056-progressive-delivery-and-safe-rollback.md) |
| Service identity & east-west zero trust | 🟡 | WireGuard transparent encryption **live both clusters** (Phase 1); Cilium mutual auth + embedded SPIRE **live on preprod** (Phase 2 showcase — the alpha-shop↔alpha-checkout call is SPIRE-authenticated, impostor denied). Fleet-wide/tier-gated enforcement pending | [057](../adrs/057-service-identity-and-east-west-zero-trust.md) |

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
[#590]: https://github.com/asanexample/platform/issues/590
