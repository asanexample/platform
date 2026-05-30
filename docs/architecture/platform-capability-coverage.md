# Platform Capability Coverage

This platform is a **reference implementation** of an internal developer platform. This page maps it
against the **13 capability domains** in the
[CNCF Platforms White Paper](https://tag-app-delivery.cncf.io/whitepapers/platforms/) (CNCF TAG App
Delivery) — an honest, current snapshot of what's built, what's partial, and what's missing, with the
issue tracking each gap.

**Legend:** ✅ Strong · 🟡 Partial · ❌ Missing

## Scorecard

| # | CNCF capability | Status | What exists / gap | Tracking |
|---|-----------------|:------:|-------------------|----------|
| 8 | Infrastructure services | ✅ | EKS (BYOCNI/Cilium), VPC + Transit Gateway, node groups, EBS CSI storage | — |
| 11 | Identity & secret management | ✅ | AWS SSO/Identity Center, per-team IAM, **EKS Pod Identity** (ADR-041) + IRSA, external-secrets → Secrets Manager, cert-manager | — |
| 12 | Security services | ✅ | Kyverno admission + RBAC/ABAC hardening, **cosign** sign/verify supply chain (ADR-014), SCPs, NetworkPolicies. *Depth gaps below* | [#108](https://github.com/asanexample/platform/issues/108) |
| 5 | Delivery & verification automation | ✅ | ArgoCD GitOps, ApplicationSet PR previews, cosign verifyImages, Kyverno admission gate | — |
| 4 | Build & test automation | ✅ | App CI (build/test/sign), the shift-left Kyverno gate (Phase 4), Terratest, platform CI | — |
| 13 | Artifact storage | 🟡 | ECR (per-team images) + GitHub (source). *Missing: generic package/binary + Helm chart registry* | — |
| 3 | Golden-path templates | 🟡 | Strong docs (ADRs, runbooks, CLAUDE.md authoring rules) + app-alpha reference app. *Missing: scaffolding ("create new app/tenant")* | [#104](https://github.com/asanexample/platform/issues/104) |
| 2 | Self-service APIs/CLIs | 🟡 | `platctl` (ops), `teams.hcl` (declarative). *But provisioning is platform-engineer-gated via PRs, not developer self-service* | [#88](https://github.com/asanexample/platform/issues/88), [#103](https://github.com/asanexample/platform/issues/103) |
| 1 | Web portal / service catalog | ❌ | ArgoCD UI shows deploy state only; no developer portal / catalog | [#103](https://github.com/asanexample/platform/issues/103) |
| 7 | Observability | ❌ | Only Hubble (network) + ArgoCD (deploy state). **No metrics/traces/logs/cost** — no *runtime* visibility | [#102](https://github.com/asanexample/platform/issues/102) (+[#93](https://github.com/asanexample/platform/issues/93)) |
| 9 | Data services | ❌ | Per-team **S3** shipped (#64); no DB/cache as a paved road | [#106](https://github.com/asanexample/platform/issues/106) |
| 10 | Messaging & event services | ❌ | None offered to tenants | [#107](https://github.com/asanexample/platform/issues/107) |
| 6 | Development environments | ❌ | PR *preview* envs exist; no developer *dev* environments / hosted IDEs | [#105](https://github.com/asanexample/platform/issues/105) |

## The two strategic gaps

The platform has a **strong foundation** — infrastructure, identity, security/supply-chain, and GitOps
delivery are genuinely solid and several are reference-grade. The gaps cluster into two themes:

1. **The developer-experience / self-service layer** (the "Vercel-like" IDP goal): a **portal** (#1,
   [#103]), true **self-service** (#2, [#88]), **golden-path scaffolding** (#3, [#104]), and **dev
   environments** (#6, [#105]). Today everything routes through platform-engineer PRs to `teams.hcl`.
2. **Observability** (#7, [#102]) — the standout single gap. Everything today is admission-time /
   GitOps-time; there is no runtime metrics/traces/logs/cost visibility.

Secondary: **paved-road data & messaging services** (#9/#10, [#106]/[#107]) — extend the per-team
isolation pattern proven for S3 in #64 — and **security depth** (#12, [#108]: SBOM, SLSA, runtime
detection, SAST/SCA).

## Notes

- "Strong" reflects *that the capability exists and is multi-tenant-isolated*, not that it is exhaustive.
- The per-team isolation pattern (declare in `teams.hcl` → Terragrunt module → EKS Pod Identity,
  default-deny by construction — see [ADR-041](../adrs/041-pod-identity-for-tenant-workloads.md)) is the
  intended template for the missing data/messaging paved roads (#106/#107).
- This page should be updated as gaps close; treat the linked issues as the backlog.

[#88]: https://github.com/asanexample/platform/issues/88
[#102]: https://github.com/asanexample/platform/issues/102
[#103]: https://github.com/asanexample/platform/issues/103
[#104]: https://github.com/asanexample/platform/issues/104
[#105]: https://github.com/asanexample/platform/issues/105
[#106]: https://github.com/asanexample/platform/issues/106
[#107]: https://github.com/asanexample/platform/issues/107
[#108]: https://github.com/asanexample/platform/issues/108
