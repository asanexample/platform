# Platform Roadmap

The single forward-looking map of the platform: **everything shipped and everything planned**, organized by
**functional area** (the *what*) and **horizon** (the *when*). This is the navigable narrative;
[GitHub Issues](https://github.com/asanexample/platform/issues) remains the system of record for live status and
detail. "Complete picture" means every capability and area is represented — not every ticket.

## Revision History

| Date       | Version | Author    | Notes                                                                  |
|------------|---------|-----------|------------------------------------------------------------------------|
| 2025-04-08 | 0.1     | J. Deeden | Initial draft of roadmap                                               |
| 2025-05-15 | 0.2     | J. Deeden | Updated for AWS Organizations, SCPs, and state management             |
| 2026-06-18 | 1.0     | J. Deeden | Consolidated to a capability map (Area × Horizon); backfilled shipped work, reframed to the current AWS IDP, retired stale multi-cloud status tables |
| 2026-06-23 | 1.1     | J. Deeden | Added Compute & Elasticity (Karpenter, ADR-078, #643); observability data plane marked complete |
| 2026-06-25 | 1.2     | J. Deeden | Added Reliability & Tech Debt to Next (epic #769, tech-debt audit inventory)          |
| 2026-06-27 | 1.3     | J. Deeden | Added the Identity & Access Strategy north-star (workforce-first model + scale-hardening) and the graduated agent-autonomy access model (ADR-086); framed I&A Phase-1 = People roster + AWS generator (closes #647) |
| 2026-06-27 | 1.4     | J. Deeden | Correction: #647 is per-team *cluster* (kubectl) access — resolved by OIDC cluster auth (#364), not the Identity Center generator (AWS console access is a separate plane); I&A Phase-1 reframed as roster + AWS **and** Keycloak generators |
| 2026-06-27 | 1.5     | J. Deeden | Linked the I&A workforce-build epic (#884) + Phase-1 sub-issues (#885–#890) into the Identity & Access area |
| 2026-06-28 | 1.6     | J. Deeden | Moved shipped work into Shipped: zero-downtime/ADR-085 (replica-floor Enforce), Argo Rollouts/ADR-056, I&A Phase-1 (#885–#890), PagerDuty/owner-routing ADR-084, Keycloak hardening ADR-087; ADR-088 temporary-power to Now; Karpenter Phase-1 marked live; closed Tier-1 issues (#770/#771/#772/#647) marked done; #647 re-pointed to #364 |
| 2026-07-01 | 1.7     | J. Deeden | Correction: PR preview environments (ADR-032) was wrongly marked Shipped — it was never implemented on the v3 delivery model (issue #721); moved to Now, split out the genuinely-shipped per-Product ApplicationSets as their own line |
| 2026-07-01 | 1.8     | J. Deeden | PR preview environments (ADR-032) re-implemented and proven end-to-end against a real PR (asanexample/alpha-shop#14); moved from Now back to Shipped; closes issues #721 and #111 |
| 2026-07-05 | 1.10    | J. Deeden | Added **Security & Hardening** to Now: secret rotation (#811) design drafted ([ADR-094](docs/adrs/094-secret-rotation-strategy.md), PR #1177); Phase-1 primitives (Reloader, rotation-age alerts, ESO refresh tiers) flagged authorable-while-parked; annotated the #1152 gap register. |
| 2026-07-07 | 1.11    | J. Deeden | Reframed the ADR-057 Phase 2 (east-west mTLS) follow-up: extending mutual auth to platform services / fleet-wide is **deliberately deferred, not owed backlog** — marginal value over WireGuard + identity-based netpol on a single cluster; the real trigger is multi-cluster (#379). |
| 2026-07-07 | 1.12    | J. Deeden | P13 reconciled to verified state + **metrics hard isolation ENFORCED**: `observability-tenant-proxy` is now the enforced front door for metrics (all prometheus datasources → proxy via `oauthPassThru`, un-proxied `mimir`/`mimir-preprod`/`mimir-all` bypass removed, fail-closed 401 verified live). Corrected prior "inert" phrasing (write-path was live-wired, just ineffective) and flagged the per-team dashboards as soft label-filters. Remaining P13 = cross-team grants + logs/traces/profiles isolation. |
| 2026-07-03 | 1.9     | Triage sweep | Full issue-board reconciliation against primary sources. Observability: corrected P13 (#590) from "designed + paused" to **built-but-metrics-only** (logs/traces/profiles isolation still unbuilt); marked P11 cost (#589) and true-spend CUR→Athena (#668) shipped/closed. Added the **alerting/blindspots epic (#1124, #1119–#1123)** to Now — previously absent. Added Shipped capabilities that were missing: **CNPG database backups (Barman Cloud, ADR-054; all three platform DBs, #1119)**, **descheduler node-rebalancing (ADR-093, #1106)**, **true cloud cost CUR→Athena (#668)**, and **kube-bench CIS EKS scan (preprod, #1158/#1149)**. FinOps: #1054/#1056 shipped, #668 closed. Tech-debt: provider-constraint standardization (#773) closed, residual → #980; gitleaks secret-scanning (#1148) shipped/closed. |

## Executive Summary

An internal developer platform that turns Kubernetes primitives into a governed, self-service paved road for
product teams. Built as infrastructure-as-code (OpenTofu + Terragrunt) with EKS, Cilium, Crossplane, ArgoCD,
Kyverno, Keycloak, and a Backstage portal. The platform currently targets **AWS** (earlier Azure/GCP scaffolding
has been removed); it is **designed to be multi-cloud-capable**, with additional providers on the roadmap rather
than in scope today.

### Vision

A platform that:

- Gives developers a **simple, self-service experience** — provision products, environments, and cloud resources
  through a portal or git, without touching the underlying infrastructure.
- Provides **enterprise-grade security, compliance, and governance by default** — least-privilege identity,
  policy-as-code admission, signed supply chain, compliance tiers.
- Keeps **platform engineers in control** of what runs underneath, via curated golden paths and a governed claim
  boundary between developer intent and safe realization.
- **Reduces operational toil** through automation, GitOps, and standardized deployment patterns.
- **Optimizes and makes visible** cloud spend, and delivers resilience as the platform matures.

Our differentiation is the combination of a **polished developer-delivery experience** with a **governed,
infrastructure-and-compliance control plane** (Terraform/Terragrunt + Crossplane-derived least-privilege IAM +
Kyverno) — the substrate, not just the surface.

## How this roadmap works

- **Two axes.** **Area** (13 functional areas) is the map — the primary way to navigate. **Horizon**
  (Now → Next → Later → Done) is the timeline.
- **Diamond granularity.** Coarse for **shipped** work (one bullet per *capability*, ≈ an ADR cluster/epic — not
  per commit), fine for **Now/Next** (real, linked issues we steer by), coarse again for **Later** (themes and
  per-area backlogs, intentionally not over-specified).
- **Source-of-truth split.** This document is the narrative map; **GitHub Issues** is live status/detail. They are
  kept in step (see *Maintenance*).
- **Roadmap-driven.** New work is picked from **Now / Next**; when a capability ships it moves to **Shipped** and
  its issue closes.

---

## Forward roadmap

What we steer by. Items link their tracking issue; see [GitHub Issues](https://github.com/asanexample/platform/issues) for live status.

### Now

*Actively in flight or next-up.*

#### Observability

- [#102](https://github.com/asanexample/platform/issues/102) Observability stack (epic) — metrics, logs, traces, profiles, cost. **Data plane COMPLETE — LGTM+P, multi-cluster, federated, correlated.** Live: P1 metrics+dashboards, P2 Mimir durable store, P3 logs+traces ([#582](https://github.com/asanexample/platform/issues/582)), P4 alerting + Slack/PagerDuty ([#583](https://github.com/asanexample/platform/issues/583)), P5 cloud-resource metrics ([#584](https://github.com/asanexample/platform/issues/584)), **P6 APM correlation** (service graph + exemplars + Traces Drilldown), **P7 instrumentation** (Beyla eBPF, [#586](https://github.com/asanexample/platform/issues/586) / [ADR-077](docs/adrs/077-application-instrumentation-strategy.md)), **P8 continuous profiling** (Pyroscope, both clusters, traces↔profiles — [#587](https://github.com/asanexample/platform/issues/587)/#637), **P9 SLOs + synthetics** (Sloth + blackbox + k6 — [#588](https://github.com/asanexample/platform/issues/588)), P10 metrics spoke + the cross-cluster Gateway edge generalized to logs/traces/profiles, P11 in-cluster cost ([#589](https://github.com/asanexample/platform/issues/589), shipped/closed) + true cloud cost CUR→Athena ([#668](https://github.com/asanexample/platform/issues/668), shipped/closed), P12 policy-reporter, and **Grafana SSO via Keycloak** ([#592](https://github.com/asanexample/platform/issues/592)/#638). **Remaining = the access plane: P13 per-team isolation ([#590](https://github.com/asanexample/platform/issues/590)) — METRICS hard isolation now ENFORCED (2026-07-07): all Grafana prometheus datasources route through the `observability-tenant-proxy` (`oauthPassThru` → identity-scoped `X-Scope-OrgID`), the un-proxied `mimir`/`mimir-preprod`/`mimir-all` bypass paths are gone, and the proxy is fail-closed (no/invalid token → 401). Still open: (a) cross-team read GRANTS + Grafana dashboard sharing (tenant-per-signal, modeled as AccessGrants); (b) the same hard isolation for logs (Loki) / traces (Tempo) / profiles (Pyroscope) — currently metrics-only.** + P14 self-service ([#591](https://github.com/asanexample/platform/issues/591) — needs re-scoping off the retired `teams.hcl` onto the v3 registries) + small polish (#151/#595/#93/#161, multi-account CloudWatch).
- Agent / GenAI observability layer (ADR-076) rides the #102 backbone — OTel-GenAI conventions, per-invocation agent traces, data-boundary content rules.
- [#1124](https://github.com/asanexample/platform/issues/1124) **Epic: close alerting blindspots (dead-man's switch, coverage, detection, routing).** The dead-man's switch is live (Watchdog → external heartbeat, #1128/#1131). In flight: P0 CNPG backup/replication/failover alerting ([#1119](https://github.com/asanexample/platform/issues/1119) — the **backup** half is done for all three DBs; the **metrics+alerting** half remains) and severity re-triage ([#1120](https://github.com/asanexample/platform/issues/1120)); P1 semantic control-plane/stateful alerts ([#1121](https://github.com/asanexample/platform/issues/1121)) and blackbox synthetic probes + cert-expiry ([#1122](https://github.com/asanexample/platform/issues/1122), probes wired, alerts pending); P2 breadth + hygiene ([#1123](https://github.com/asanexample/platform/issues/1123)).

#### Compute & Elasticity

- [#643](https://github.com/asanexample/platform/issues/643) **Cluster elasticity — Karpenter + workload autoscaling ([ADR-078](docs/adrs/078-cluster-elasticity-karpenter.md)).** Closes the biggest operational gap: the clusters don't autoscale at any layer. **Phase 1 shipped/live** — Karpenter node autoscaling on both clusters (conservative `on-demand`/`WhenEmpty` on the stateful platform hub; spot retired in favour of `on-demand`/`WhenEmptyOrUnderutilized` on preprod), with BYOCNI startup-taint ordering + `platctl` park-awareness. **Phase 2 (in flight)** — HPA/KEDA on the paved road (a default HPA emitted by the golden path) so the loop closes: HPA adds pods → Karpenter adds nodes → consolidation reclaims.

#### Identity & Access

- **Temporary-power activation / JIT elevation ([ADR-088](docs/adrs/088-temporary-power-activation.md)).** Eligibility-in-git + timed activation + revocation for dangerous power (break-glass). Foundation merged — `platctl access list`/`access check <person> <role>` + break-glass eligibility (#943/#945/#946); remaining activation/revocation flow in flight.

#### Security & Hardening

- [#811](https://github.com/asanexample/platform/issues/811) **Secret rotation ([ADR-094](docs/adrs/094-secret-rotation-strategy.md)).** Tier-1 gap from the security-posture register (epic [#1152](https://github.com/asanexample/platform/issues/1152)): all 23 platform + 3 preprod Secrets Manager secrets are unrotated (`Rotation: null`). **Design half drafted** — ADR-094 (Proposed, PR [#1177](https://github.com/asanexample/platform/pull/1177)): a classification-driven strategy (Terraform-two-sided / external-provider / already-keyless / tenant) on the existing **ESO + Secrets Manager + Pod Identity** seam, **no Vault**. The reframe: identity creds are already keyless (SSO/OIDC/Pod Identity) — the gap is static credential *values* + three missing primitives. **Phase 1 is authorable-while-parked** — the shared primitives: a cluster-wide **Reloader** (restart-on-change), **rotation-age metrics + alerts** into LGTM+P, and the **ESO refresh-interval tiers** ADR-024 defined but never wired. Build phases (2 Class-A Terraform-driven rotation → 3 Class-B provider-specific + retire the `argocd-pat` → 4 tenant/ADR-070) remain; **verification gated on cluster unpark, preprod-first** — nothing live yet.

#### Documentation & Enablement

- **Learning portal — a teaching layer for the platform (`docs/learn/`).** The corpus explains (reference for people who already hold the model) but doesn't *teach* it from the ground up. New: per-subsystem courses on a shared mold — **Orientation** (journey) + **Reference** (lookup) + optional **Deep dives** (one hard mechanism) + **Tutorials** (hands-on) + a portal **Glossary** — built one subsystem at a time, eventually served in Backstage TechDocs (wiring is #938). **Shipped — the domain model + the Environment API (Crossplane)** incl. the first deep dive (Composition rendering) and offline tutorial; proving the format before scaling to observability, delivery, policy, identity, supply-chain, cost, and a control-plane spine.
- **Learning sandbox — the hands-on surface for tutorials (future enabler).** Tutorials run *offline* today (`crossplane render`, zero infra); the live "provision it for real, watch it self-heal" experience needs a safe sandbox. Design options: a scoped **"learning" Team on existing preprod** (tiny envelope + mandatory TTL + `$` budget cap — cheapest, reuses the env-api's own guardrails) vs. a **dedicated sandbox account** (harder blast-radius isolation; the Terratest Test account `157263244316` is precedent). Reuses ADR-091 cost caps, Cloud Custodian cleanup (#1058), and the ADR-032 ephemeral-env mechanism. Not built — tutorials are explicitly marked *provisional* until it lands.

### Next

*Queued and build-now — near-term build order.*

#### Observability

- [#629](https://github.com/asanexample/platform/issues/629) **Epic: single pane of glass — multi-cluster, all signals.** **Collection + read-federation DONE** — the Gateway-native spoke edge is replicated across every store and one Grafana spans platform + preprod, broken out by `cluster`, with correlation intact:
  - [#626](https://github.com/asanexample/platform/issues/626) Mimir federation + multi-cluster dashboards ✅ · [#627](https://github.com/asanexample/platform/issues/627) Logs spoke ✅ · [#628](https://github.com/asanexample/platform/issues/628) Traces spoke ✅ · profiles spoke ✅ (#637) · uniform `cluster` label ✅ ([#630](https://github.com/asanexample/platform/issues/630))
  - **Remaining = the access half: P13 per-team isolation ([#590](https://github.com/asanexample/platform/issues/590)) — METRICS hard isolation ENFORCED (2026-07-07); grants + other signals in flight.** Decision: re-tenant by team (hard boundary; Enterprise ruled out). Shipped 2026-07-02/03: write-path re-tenant (`observability-cortex-tenant`), read-side identity→tenant proxy (`observability-tenant-proxy`) + per-team Grafana datasource, a second tenant for isolation testing, and per-team overview dashboards (#1126–#1157). **2026-07-07: the proxy is now the ENFORCED front door for metrics — every prometheus datasource routes through it (identity-scoped, fail-closed), no un-proxied bypass remains. Still open: (a) cross-team read GRANTS (tenant-per-signal federated read + Grafana dashboard sharing, modeled as AccessGrants); (b) the same hard isolation for logs (Loki) / traces (Tempo) / profiles (Pyroscope)** — currently metrics-only. Full plan in the #590 design comment.

#### GitOps & Delivery

- [#502](https://github.com/asanexample/platform/issues/502) P2.6: multi-service Request Promotion template
- **Immutable release + environment-binding promotion** — Net-new delta. Builds ON the shipped Release-CRD digest promotion (ADR-071) + release-keyed ApplicationSet (#495, done) + promotion ladder (#377). New = an immutable release as the artifact and a binding as the promotion/rollback primitive (rollback = re-point the binding).

#### Developer Portal

- [#285](https://github.com/asanexample/platform/issues/285) BACK P5: provisioning visibility — polished experience (ADR-064)
- [#356](https://github.com/asanexample/platform/issues/356) Backstage: unified "in-flight" view of teams/tenants (open requests + provisioning-not-Ready)
- **Golden paths as first-class API objects** — Net-new delta. Today paved roads are scaffolder cookiecutter templates (shipped, ADR-062). New = model golden paths as queryable, composable platform API objects the platform reasons about. Relates #358 (add service to existing repo).

#### Environment & Resource Control Plane

- [#391](https://github.com/asanexample/platform/issues/391) Secrets paved-road: tenant app config & secrets (ADR-070)

#### Cost & FinOps

- [#1052](https://github.com/asanexample/platform/issues/1052) **Platform FinOps practice (epic) — adopt the FinOps Framework ([ADR-092](docs/adrs/092-platform-finops-practice.md)).** The operating model (Inform → Optimize → Operate) for the platform's **own** cost, above the per-team guardrails (ADR-091, shipped). Free OSS/native only (no spend budget); Savings Plans + paid tiers documented-but-deferred. Workstreams — **shipped/closed:** AWS Budgets + Cost Anomaly Detection ([#1054](https://github.com/asanexample/platform/issues/1054)), Infracost shift-left cost-in-PR ([#1056](https://github.com/asanexample/platform/issues/1056)), true-spend CUR→Athena ([#668](https://github.com/asanexample/platform/issues/668)). **Still open:** platform-shared cost bucket ([#1053](https://github.com/asanexample/platform/issues/1053)), Compute Optimizer rightsizing ([#1055](https://github.com/asanexample/platform/issues/1055)), kube-green off-hours idle spike ([#1057](https://github.com/asanexample/platform/issues/1057)), Cloud Custodian account janitor spike ([#1058](https://github.com/asanexample/platform/issues/1058)), FinOps cadence + forecasting ([#1059](https://github.com/asanexample/platform/issues/1059)), Slack cost-alert delivery ([#1063](https://github.com/asanexample/platform/issues/1063)).

#### Reliability & Tech Debt

- [#769](https://github.com/asanexample/platform/issues/769) **Epic: tech-debt paydown — 2026 H2 inventory.** Deep 10-pass audit (~150 `TD-NNN` findings; the dated audit snapshots are retired — see git history). Tier 1 (security/correctness, spot-verified) — **all four done/closed:** enforce cosign on the hub ([#770](https://github.com/asanexample/platform/issues/770) ✅), private-only EKS default ([#771](https://github.com/asanexample/platform/issues/771) ✅), fail-closed gate scripts ([#772](https://github.com/asanexample/platform/issues/772) ✅), DeveloperAccess regression ([#647](https://github.com/asanexample/platform/issues/647) — closed as superseded by OIDC-native cluster auth [#364](https://github.com/asanexample/platform/issues/364); capability still unbuilt). Tier 2 (systemic) — **done/closed:** provider-constraint standardization ([#773](https://github.com/asanexample/platform/issues/773), residual stragglers → [#980](https://github.com/asanexample/platform/issues/980)), `.tool-versions` SSOT ([#774](https://github.com/asanexample/platform/issues/774)), Azure-carcass removal ([#775](https://github.com/asanexample/platform/issues/775)), Action SHA-pinning ([#776](https://github.com/asanexample/platform/issues/776)). **Deferred:** Dependabot coverage ([#777](https://github.com/asanexample/platform/issues/777)), tests-into-PR-gates ([#778](https://github.com/asanexample/platform/issues/778)). Security/IAM findings fold into the existing tracker [#654](https://github.com/asanexample/platform/issues/654). The second-pass live-state audit (epic [#809](https://github.com/asanexample/platform/issues/809), TD2-NN) is burning down — CNPG backups (#1119) done, preprod Kyverno HA (#812) + right-sizing (#818) outstanding.

### Later

*On the map; not yet scheduled or blocked on a dependency (e.g. the planned rebuild).*

#### Network & Connectivity

- **Network hardening backlog** — Rollup -> filter label:area/network. Includes #162 WireGuard pod encryption, #163 node subnet sizing, #166 Kyverno HA hostNetwork, #206 subnet-router after scale-up.

#### Kubernetes & Ingress

- **Autoscaling** — Workload + cluster autoscaling as a paved-road capability (HPA/VPA/Karpenter-class), governed and surfaced through the platform abstractions.

#### Identity & Access

- **Identity & Access Strategy — north-star (design-of-record landed; Phase-1 build SHIPPED — epic [#884](https://github.com/asanexample/platform/issues/884), subs #885–#890 all closed; see Shipped → Identity & Access).** The unified workforce-first model in [`docs/architecture/identity-and-access-strategy.md`](docs/architecture/identity-and-access-strategy.md): decide access once → derive → project into every system (AWS, apps, GitHub, PagerDuty, Slack) from one git source of truth (Teams + **People** + Grants); dangerous power borrowed temporarily (eligibility-in-git + timed activation); auth strength scaling with role; plus the honest scale-hardening (intent-vs-effected verification, decide/apply split, drift detection, meta-governance). **Phase 1 (highest value-per-effort) shipped = the People roster + deriving AWS (Identity Center console) *and* Keycloak (app) access from it, retiring the hand-maintained HCL/seed-users so "add a person" is one PR.** (The per-team *cluster*-access regression [#647](https://github.com/asanexample/platform/issues/647) is a separate plane — **closed as superseded** by OIDC-native cluster auth [#364](https://github.com/asanexample/platform/issues/364), not the Identity Center generator; the capability itself is still unbuilt.) The ADR-068 P4 items below (#361–#368) realize the access-model core; the machine/agent plane defers to ADR-074 + the graduated-autonomy model ([ADR-086](docs/adrs/086-autonomous-agent-access.md), see Agentic Workloads). **CIAM (customer identity) is a named, deferred plane.**
- [#361](https://github.com/asanexample/platform/issues/361) P4 (ADR-068): Product-scoped & cross-team access model
- [#362](https://github.com/asanexample/platform/issues/362) P4.1 (ADR-068): AccessGrant CRD + cluster projection
- [#363](https://github.com/asanexample/platform/issues/363) P4.2 (ADR-068): Access-model-as-code — Product roles in Keycloak
- [#364](https://github.com/asanexample/platform/issues/364) P4.3 (ADR-068): OIDC-native developer cluster auth (EKS OIDC IdP)
- [#365](https://github.com/asanexample/platform/issues/365) P4.4 (ADR-068): Fan-out — ArgoCD RBAC + Backstage permissions from product roles
- [#367](https://github.com/asanexample/platform/issues/367) P4.6 (ADR-068): team-admin governance + grant lifecycle (request/TTL/re-attest)
- [#368](https://github.com/asanexample/platform/issues/368) P4.7 (ADR-068): Two-plane grant enforcement (access-grant-gate CI + Kyverno)
- **East-west zero-trust (ADR-057)** — **Phase 1 (WireGuard transparent encryption): shipped + live on both clusters 2026-07-07** ([#162](https://github.com/asanexample/platform/issues/162); fleet-default, pod-to-pod; verified `Encryption: Wireguard` + end-to-end HTTP 200 through the encrypted mesh). **Phase 2 (Cilium mTLS + SPIFFE workload identity): showcase built + live on preprod 2026-07-07** ([#1201](https://github.com/asanexample/platform/issues/1201); embedded SPIRE; the `alpha-shop → alpha-checkout` path is SPIRE-mutually-authenticated (`AUTH TYPE=spire`), cross-team impostor denied). Extending mutual auth beyond the preprod showcase — fleet-wide or onto platform services — is **deliberately deferred, not owed backlog**: on a single trusted cluster it adds little over the WireGuard encryption + Cilium's already-identity-based network policy that platform services get today; the property it *uniquely* adds (cryptographic SPIFFE workload identity) only earns its keep across a trust boundary the datapath identity can't span. The real trigger is therefore **multi-cluster / cross-mesh service calls** ([#379](https://github.com/asanexample/platform/issues/379) Placement / multi-cluster), where tier-gated enforcement rides along — not a standalone follow-up.

#### Governance & Supply-chain

- **Kyverno policy backlog** — Rollup -> filter label:area/policy. Includes #77 CEL ValidatingPolicy, #78 PolicyException governance, #79 HIPAA/PCI packs, #80 kyverno-json, #81 multi-cluster distribution, #82 nodeSelector validation, #93 PolicyReport observability.
- **Security posture gap register — epic [#1152](https://github.com/asanexample/platform/issues/1152).** The [Security Model spine doc](docs/learn/spine/the-security-model.md)'s honest, top-to-bottom **4 C's** gap register (Cloud/Cluster/Container/Code), with a proposed prioritization. **Tier 1 (next up):** EKS audit logging ([#816](https://github.com/asanexample/platform/issues/816)), secret-scanning in CI ([#1148](https://github.com/asanexample/platform/issues/1148)), WAF ([#1147](https://github.com/asanexample/platform/issues/1147) — **architecture decided: edge-first via Cloudflare ([ADR-096](docs/adrs/096-web-application-firewall-edge-first.md)); implementation deferred (paid tier) per the no-spend posture**), secrets rotation ([#811](https://github.com/asanexample/platform/issues/811) — **design drafted ([ADR-094](docs/adrs/094-secret-rotation-strategy.md)); Phase-1 primitives promoted to Now**). New gaps filed from the doc audit: WAF #1147, secret-scanning #1148, CIS/kube-bench #1149, SIEM #1150, pentest #1151.
- **Security & hardening backlog** — Rollup -> filter label:security. Includes #59 _v1 rename, #70 prod least-privilege, #111 ArgoCD GitHub App, #118 customer KMS CMKs, #129 SCA/AppSec, #132 CSPM, #152 state-bootstrap S3, #196 Backstage ns hardening, #213 token rotation, #242 EBS orphans, #243 chart-repo resilience, #273 CoreDNS.

#### GitOps & Delivery

- [#500](https://github.com/asanexample/platform/issues/500) P2.4 (ADR-056): progressive delivery for prod — Argo Rollouts. **Core SHIPPED** (see Shipped → GitOps & Delivery); #500 retained for residual prod-hardening only.
- **Rollback resilience & database migrations** — Net-new, undecided. The GitOps "revert the commit" rollback is clean only for *stateless* change; a release that ran a schema migration can't be undone by reverting code (down-migrations are lossy/impossible), and the canary already runs two app versions against one DB — so schema backward-compatibility is a **latent, unenforced precondition of progressive delivery itself**, not just a rollback nicety. Needs an app **rollback-resilience contract** (additive expand/contract migrations, migrations decoupled from deploy, N-1 compatibility) and likely a managed tenant-database offering (self-service data is S3/SQS/DynamoDB today, ADR-073). Surfaced writing the *Life of a Deployment* spine doc.
- **Versioning & compatibility contracts** — Net-new, undecided; vague across the platform today. Facets: (1) **service/release version identity** — deploys are digest-only, no human-facing semver/release name; (2) **platform-API versioning** — evolving the `platform.refplat.org` CRDs (XEnvironment/XAgent/Team/Product/Release) past `v1beta1` without breaking live objects (storage version, conversion webhooks, deprecation policy); (3) **provisioner versioning** — rolling Composition changes across all live Environments safely (the render-cascade hazard); (4) **compatibility/skew contracts** — N-1 app↔schema (see rollback resilience) and API↔consumer skew. Unifying theme with rollback resilience: **compatibility across versioned boundaries** — candidate for one strategy/ADR.

#### Developer Portal

- [#177](https://github.com/asanexample/platform/issues/177) BACK stack P6: Backstage plugins (ArgoCD, Crossplane, Kyverno, Grafana)
- [#200](https://github.com/asanexample/platform/issues/200) Represent the Terraform/Terragrunt platform infra in the Backstage catalog
- **Higher-altitude developer abstraction** — Net-new. Developers declare intent (e.g. an internal HTTP endpoint); the platform synthesizes HTTPRoute + NetworkPolicy + policy-compliant wiring, vs near-raw manifests. Relates #375 (platform-injection).

#### Agentic Workloads

- **Status: design-of-record landed, at rest.** ADR-074/075/076 (Proposed) + de-risking spikes 1–3 done (all GO); [#554](https://github.com/asanexample/platform/issues/554) tier-0 resource agent epic is build-gated. **Resume trigger:** a concrete, wanted *second* agent → run the eval-feasibility probe. Substrate pulled by demand, not pushed.
- **Substrate primitives** — Agent CRD + three-identity authority (intersection + attenuating delegation) + tiered disposition + LLM data-boundary + model-gateway metering seam + eval-as-a-service + kill-switch (ADR-074). Built after tier-0 + a decision gate.
- **Autonomous / multi-agent (A2A)** — autonomous agents + agent-to-agent, behind a mature safety substrate (eval-as-a-service + kill-switch live). The **graduated-autonomy access model** ([ADR-086](docs/adrs/086-autonomous-agent-access.md), extending ADR-074) governs how an agent earns *bounded, reversible, machine-guarded* autonomy — e.g. real-time alert remediation — replacing the human gate with machine-enforced bounds rather than removing it; propose-only is the tier-0 floor, not the ceiling. Depends on the **AccessGrant/P4** model (see Identity & Access, #361–#368) for cross-team/autonomous authority — the agent initiative is the forcing function to prioritize P4.
- **Deferred component picks (Spike 3)** — CaMeL/dual-LLM IPI defense + a classifier guardrail (PromptGuard/AlignmentCheck) only when an agent can *act*; Inspect + self-hosted Langfuse when the oracle disappears (multi-agent eval); a larger guardrail FP corpus. Tier-0 adopts none of these.

#### Environment & Resource Control Plane

- [#105](https://github.com/asanexample/platform/issues/105) Developer environments (ephemeral dev sandboxes / devcontainers)
- [#378](https://github.com/asanexample/platform/issues/378) P3 (ADR-067): Customers + graduated isolation
- [#379](https://github.com/asanexample/platform/issues/379) P5 (ADR-067): Placement / multi-cluster (HA/DR) + Service→Resource dependencies
- **Multi-cloud** — Extend the cloud-resource control plane + governance beyond AWS (Azure/GCP) behind the same governed-claim + derived-IAM model. Currently AWS-only.

#### Platform Tooling & Ops

- **Resilience & BC / DR posture** — Decided (ADR-054), partial. Teardown→rebuild validated (done); broader DR/business-continuity posture outstanding. Overlaps #379 placement.
- **platctl & CI backlog** — Rollup. Includes #299 platctl CI+coverage, #305 Terragrunt post-merge converge, #346 teams CI TG_DEPENDENCY_FETCH, #348 teams CI sts:TagSession.

---

## Shipped capabilities

*The capability map of what the platform does today. Each bullet ≈ one ADR cluster or epic — capability granularity, not per-commit.*

### Cloud Foundation

- **Multi-account AWS Org + SCPs + OU hierarchy** — Shipped. AWS Organizations, Service Control Policies, OU hierarchy (ADR-003/004/005). Includes CloudTrail secrets audit logging (ADR-037).
- **OpenTofu/Terragrunt monorepo + S3 state + IAM role model** — Shipped. Terragrunt hierarchy, S3 state bootstrap, PlatformAdmin/Deployer role model. ADR-001/002/006/007/016.

### Network & Connectivity

- **Private cluster access: Tailscale + SSM bastion** — Shipped. Tailscale subnet routers advertise VPC CIDR + split-DNS; SSM Session Manager bastion. ADR-011/020.
- **VPC/CIDR + DNS + Transit Gateway + cross-VPC DNS** — Shipped. CIDR strategy, Route53/Cloudflare delegation, TGW hub-spoke, cross-VPC DNS resolution. ADR-015/022/034/035.

### Kubernetes & Ingress

- **Cilium CNI — kube-proxy replacement, netpol, Gateway API** — Shipped. Cilium 1.19, kubeProxyReplacement, network policy, Cilium Gateway API. ADR-008/017.
- **Private EKS (BYOCNI) + node groups + managed addons** — Shipped. Private-only API EKS, BYOCNI ordering, separated node groups + coredns addon. ADR-009/010/023.
- **Shared Gateway + cert-manager + external-dns** — Shipped. Foundational shared Gateway + ClusterIssuer, Let's Encrypt DNS-01, external-dns. ADR-029/030/059/060/061.
- **Zero-downtime / graceful-disruption defaults** — Shipped, live both clusters. Kyverno-injected graceful-drain (`preStop` + `terminationGracePeriodSeconds`), generated PodDisruptionBudgets, topology-spread defaults, Karpenter drain backstop, and the `*-prod` replica-floor flipped **Audit→Enforce** (#844). ADR-085.

### Identity & Access

- **EKS Pod Identity for workload AWS access** — Shipped. Pod Identity associations replace IRSA annotations for environment workloads. ADR-041/047.
- **Keycloak IdP + OIDC consolidation (Dex/oauth2-proxy retired)** — Shipped. Keycloak as IdP-of-record, OIDC for ArgoCD+Backstage, retired Dex+oauth2-proxy. ADR-052/053/059.
- **Per-team developer RBAC + platform-engineer access model** — Shipped. DeveloperAccess-<team> namespace-scoped RBAC; PlatformAdmin operate-not-author. ADR-039/040.
- **Identity & Access Phase 1 — People roster + derived AWS/Keycloak access** — Shipped (epic #884, subs #885–#890 all closed). Git-native People registry + role catalog; Identity Center (AWS console) generator and Keycloak (app) generator both derived from the roster, retiring hand-maintained HCL/seed-users; auth-strength MFA scaling. ADR-086.
- **Workforce directory + owner-resolution + per-team PagerDuty on-call** — Shipped. The `platform-directory` identity directory + owner-routing agent resolve a culprit's owning team; the `pagerduty` module provisions per-team on-call schedules/escalation in IaC. ADR-084 (#932).
- **Keycloak admin-plane hardening** — Shipped. Passkey-bound master-realm admin flow + bootstrap-admin seal. ADR-087 (#899/#930/#935/#941).

### Governance & Supply-chain

- **Compliance-tier model + SOPS-encrypted config secrets** — Shipped. standard/pci/hipaa tiers drive config; SOPS/KMS committed secrets. ADR-013/055/066.
- **Keyless cosign signing + SBOM + SLSA L3 provenance** — Shipped. cosign keyless signatures, CycloneDX SBOM, SLSA Build L3 provenance, verify at admission. ADR-042/050.
- **Kyverno admission engine + Audit→Enforce rollout** — Shipped. Kyverno HA engine + ClusterPolicies, phased Audit→Enforce on preprod+platform. ADR-014.
- **Per-product image scoping + supply-chain split** — Shipped. Kyverno restrict-images per Product registry; platform-owned cosign verify vs product-owned restrict (ADR-067). Includes ECR cross-account container registry (ADR-028).
- **Secrets management: External Secrets Operator + Secrets Manager** — Shipped. ESO + ClusterSecretStore sync from AWS Secrets Manager/SSM; secret naming convention + cross-account secret isolation. ADR-019/024/025/026.

### GitOps & Delivery

- **Per-Product delivery ApplicationSets** — Shipped. Release-keyed per-Product ApplicationSet generators (ADR-069, #377).
- **PR preview environments** — Shipped, proven end-to-end 2026-07-01. A `pullRequest`-generator ApplicationSet per opted-in Product deploys into the existing `dev` namespace off the already-signed PR-tagged image, isolated by kustomize `namePrefix`/`commonLabels`, and auto-cleans up on PR close. ADR-032; closes issues #721 and #111.
- **ArgoCD GitOps + per-team AppProjects/RBAC** — Shipped. ArgoCD delivery engine, per-team AppProjects, SSO RBAC. ADR-021.
- **Multi-stage promotion: auto ≤ staging + gated prod** — Shipped (P2). Promote-by-digest, auto-promote reconciler ≤ staging, gated prod. ADR-067 P2 / #377.
- **Release-CRD digest promotion + Product-registry source-of-truth** — Shipped. Image-digest promotion via control plane (protected-main); Product registry + Environment claims drive delivery. ADR-069/071.
- **Progressive delivery — Argo Rollouts (canary/blue-green)** — Shipped (core). `argo-rollouts` controller for all workloads, metric-gated canary + burn-rate SLO analysis, freeze gate, and the Rollouts dashboard fronted by `oauth2-proxy` for Keycloak SSO. ADR-056 (#500 retained for residual prod-hardening).

### Developer Portal

- **Backstage portal + catalog + direct Keycloak OIDC** — Shipped. Backstage at backstage.aws.refplat.org, catalog, direct Keycloak OIDC signin. ADR-051.
- **Catalog projection + live K8s/ArgoCD/MR status + RBAC** — Shipped. v3 projection (Product=System/Service=Component/Environment), live K8s+ArgoCD plugins + namespaced-MR status (#574), Keycloak-group RBAC (#197). ADR-064.
- **Scaffolder: New Product/Team/Resource templates + multi-language starters** — Shipped. Self-service scaffolder templates (Product/Team/Resource/deprovision) + Go/Node/Python/Java/Rust/Rails starters. ADR-062.

### Environment & Resource Control Plane

- **Crossplane Environment API + v3 domain-model cutover** — Shipped. XEnvironment XRD+Composition; v3 Team/Product/Service/Environment cutover. ADR-048/067.
- **Live resource status — namespaced MRs in catalog** — Shipped. Tenant resource plane on namespaced aws.m.upbound.io MRs, live status in Backstage. #574.
- **Safe environment/product deprovisioning lifecycle** — Shipped. Reversible decommissioning suspend; admin-gated hard-delete; ECR orphaned. ADR-062.
- **Self-service cloud resources: S3/SQS/SNS/DynamoDB + derived IAM** — Shipped. Governed-claim resources with curated Compositions + DERIVED least-privilege IAM. ADR-073.

### Domain Model & Ownership

- **App-repo naming + GitHub org-Team ownership** — Shipped. Dropped app- prefix; GitHub org Teams own app repos, registry-derived. ADR-072 (epic #532).
- **Team→Product→Service→Environment model + git-native Team registry** — Shipped. ADR-067 domain model; git-native Team CR + Product/Environment registries as source of truth. ADR-063/067.

### CI & Build

- **GitHub OIDC federation for CI** — Shipped. Keyless GitHub Actions OIDC to AWS for CI/CD. ADR-036.
- **Self-hosted ARC runners + shared trusted-ci build-sign** — Shipped. Actions Runner Controller in-VPC CI; shared trusted-ci build-sign/SLSA reusable workflows. ADR-050/065.

### Observability

- **Falco runtime threat detection** — Shipped. Falco eBPF runtime threat detection on **preprod + platform** clusters. ADR-045. (#116, #149.)
- **Prometheus/Grafana stack + Mimir durable metrics** — Shipped (P1+P2). kube-prometheus-stack + Grafana; Mimir S3-backed durable metrics via remote-write. ADR-043/044.
- **Full LGTM+P data plane — multi-cluster, federated, correlated** — Shipped. Logs (Loki) + traces (Tempo) + profiles (Pyroscope) stores with preprod spokes shipping to the hub, uniform `cluster` label, APM correlation (service graph + exemplars), Beyla/OTel auto-instrumentation, and one federated Grafana across platform + preprod. #582–#630 / ADR-077.
- **In-cluster + true cloud cost observability** — Shipped. OpenCost per-cluster → Mimir with per-team/per-environment dashboards + budgets, plus a CUR→Athena→Grafana true-spend pipeline reconciled against OpenCost. #589/#668 (delivered under the ADR-091 cost track).
- **Dead-man's switch + core alerting** — Shipped (foundation). Watchdog routed to an external heartbeat (healthchecks) so a dead Alertmanager still pages; ArgoCD delivery-outage and ExternalSecret/SecretStore not-ready classes escalated to critical. #1128/#1131/#1125/#1127. (Broader coverage in flight — epic #1124.)

### Cost & FinOps

- **Per-environment ResourceQuota + cost-allocation tags** — Shipped baseline. Per-environment ResourceQuota; Team/Product/Stage cost-allocation tags on resources.
- **Cost guardrails — per-team budgets, attribution, phased enforcement** — Shipped (ADR-091, A+B+C live 2026-06-30). `Team.spec.envelope.budget`, OpenCost + CUR→Athena attribution, Grafana cost dashboards + Backstage Cost tab, budget burn-rate alerts → owner-routing, and audit-first Kyverno enforcement on over-budget `XEnvironment` provisioning.

### Platform Tooling & Ops

- **Validated teardown→rebuild-from-scratch** — Shipped. Repeatable full teardown+rebuild (58/58) validated; runbook + platctl automation.
- **platctl CLI — bootstrap/teardown/validate/park** — Shipped. platctl: bootstrap, teardown, lockdown/unlock, validate, kubeconfig, park/unpark (down/up); DAG-aware, with startup-ordered DB-client recovery on unpark. ADR-038.
- **CNPG database backups (Barman Cloud)** — Shipped. All three platform CloudNativePG databases (platform-directory/triage-copilot, Backstage, Keycloak) back up to S3 via the Barman Cloud plugin — per-cluster Pod-Identity IAM, SSE-encrypted (SCP-compliant), staggered daily ScheduledBackups. ADR-054 (#1119). Remaining: restore/PITR runbook + backup-failure alerting.
- **Descheduler node-rebalancing** — Shipped, live both clusters. Durable fix for post-unpark node imbalance (evicts to rebalance so Karpenter can consolidate). ADR-093 (#1106).

---

## Success Metrics & KPIs

Aspirational targets the platform is steered toward (not all instrumented yet).

### Operational

| Metric | Target | Description |
|---|---|---|
| Deployment Time | < 2 hours | Time to deploy a complete environment from scratch |
| Infrastructure Drift | 0% | Resources not managed by IaC |
| Automated Testing Coverage | > 90% | Modules covered by automated tests |
| Mean Time to Recovery (MTTR) | < 30 min | Time to recover from infrastructure failures |
| Security Findings | 0 critical/high | Open critical/high security findings |

### Platform Reliability

| Metric | Target | Description |
|---|---|---|
| Service Availability (SLA) | > 99.95% | Uptime for production services |
| Error Budget Consumption | < 80% | Allowed downtime used within SLA period |
| Recovery Success Rate | > 99% | Recovery procedures executed successfully |

### Performance

| Metric | Target | Description |
|---|---|---|
| Cluster Resource Saturation | < 80% | CPU/memory headroom across clusters |
| API Response Times | < 200ms (P95) | Latency for critical platform APIs |
| CI/CD Pipeline Execution Time | < 30 min | Commit to deployed |

### Operational Efficiency

| Metric | Target | Description |
|---|---|---|
| Mean Time to Detect (MTTD) | < 5 min | Time to detect infrastructure issues |
| Change Success Rate | > 98% | Changes implemented without incidents |
| Toil Reduction | > 30% quarterly | Hours saved through automation vs baseline |

### Security & Compliance

| Metric | Target | Description |
|---|---|---|
| Time to Patch Critical Vulns | < 24 hours | Patch time for critical vulnerabilities |
| Policy Violation Rate | < 2% | Resources violating security policies |
| Compliance Controls Coverage | 100% | Required compliance controls implemented |

### Resource Optimization

| Metric | Target | Description |
|---|---|---|
| Resource Utilization | > 65% | Actual usage vs allocated |
| Idle Resource Percentage | < 15% | Provisioned but unused resources |
| Cloud Spend Visibility | 100% | Resources with cost-allocation tags |

### Developer Experience

| Metric | Target | Description |
|---|---|---|
| Self-Service Success Rate | > 95% | Successful self-service ops vs attempts |
| Developer Onboarding Time | < 1 day | New dev to first deployment |
| Environment Provisioning Time | < 1 day | Request to fully operational environment |
| Documentation Accuracy | > 95% | Docs verified accurate and current |

---

## Prioritization Framework

### Priority Categories

| Priority | Description | Criteria |
|---|---|---|
| P0: Critical | Must-have for security, compliance, or core functionality | Security vulns • regulatory requirements • core infra dependencies |
| P1: High | Important operational capability or high business value | Core platform features • high-value features |
| P2: Medium | Significant value, not essential for MVP | Quality-of-life • performance • cost optimization |
| P3: Low | Nice-to-have features or enhancements | Additional features • further automation • optional integrations |

### Impact vs. Effort

- **High Impact / Low Effort** → implement immediately
- **High Impact / High Effort** → schedule for focused work
- **Low Impact / Low Effort** → as resources allow
- **Low Impact / High Effort** → defer

---

## Stakeholders & Governance

| Role | Representative | Responsibilities |
|---|---|---|
| Platform Lead / Cloud Operations | Josh Deeden | Strategy, implementation, module development, documentation |
| Security & Compliance | Josh Deeden | Security requirements, compliance validation |
| Platform Consumer / Requirements | Josh Deeden | Requirements input, acceptance |

*Team of one for now — Josh Deeden is the sole stakeholder across all roles. Roles are listed so responsibilities
stay explicit and can be delegated as the team grows.*

**Decision making:** strategic and technical decisions are made by the Platform Lead; security/compliance changes
are self-reviewed against the policy-as-code guardrails (Kyverno, supply-chain) that enforce them in CI and at
admission.

---

## Maintenance

- **Roadmap-driven:** new work is picked from **Now / Next** above; each item links its tracking issue.
- **When something ships:** move it out of Forward and add a one-line capability bullet under **Shipped**
  (capability granularity — not one bullet per PR), and close its issue.
- **When something new is planned:** add it under the right Area + Horizon, with an issue link if it's decomposed.
- **Keep in step:** this doc = the narrative map; GitHub Issues = live tracking/detail.
