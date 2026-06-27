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

- [#102](https://github.com/asanexample/platform/issues/102) Observability stack (epic) — metrics, logs, traces, profiles, cost. **Data plane COMPLETE — LGTM+P, multi-cluster, federated, correlated.** Live: P1 metrics+dashboards, P2 Mimir durable store, P3 logs+traces ([#582](https://github.com/asanexample/platform/issues/582)), P4 alerting + Slack/PagerDuty ([#583](https://github.com/asanexample/platform/issues/583)), P5 cloud-resource metrics ([#584](https://github.com/asanexample/platform/issues/584)), **P6 APM correlation** (service graph + exemplars + Traces Drilldown), **P7 instrumentation** (Beyla eBPF, [#586](https://github.com/asanexample/platform/issues/586) / [ADR-077](docs/adrs/077-application-instrumentation-strategy.md)), **P8 continuous profiling** (Pyroscope, both clusters, traces↔profiles — [#587](https://github.com/asanexample/platform/issues/587)/#637), **P9 SLOs + synthetics** (Sloth + blackbox + k6 — [#588](https://github.com/asanexample/platform/issues/588)), P10 metrics spoke + the cross-cluster Gateway edge generalized to logs/traces/profiles, P11 in-cluster cost, and **Grafana SSO via Keycloak** ([#592](https://github.com/asanexample/platform/issues/592)/#638). **Remaining = the access plane: P13 per-team isolation ([#590](https://github.com/asanexample/platform/issues/590), designed + paused)** + small polish (#151/#595/#93/#161, multi-account CloudWatch).
- Agent / GenAI observability layer (ADR-076) rides the #102 backbone — OTel-GenAI conventions, per-invocation agent traces, data-boundary content rules.

#### Compute & Elasticity

- [#643](https://github.com/asanexample/platform/issues/643) **Cluster elasticity — Karpenter + workload autoscaling ([ADR-078](docs/adrs/078-cluster-elasticity-karpenter.md)).** Closes the biggest operational gap: the clusters don't autoscale at any layer. **Phase 1 (in progress)** — Karpenter node autoscaling on both clusters (conservative `on-demand`/`WhenEmpty` on the stateful platform hub; aggressive `spot`/`WhenEmptyOrUnderutilized` on preprod), retiring the static spot node group, with BYOCNI startup-taint ordering + `platctl` park-awareness. **Phase 2** — HPA/KEDA on the paved road (a default HPA emitted by the golden path) so the loop closes: HPA adds pods → Karpenter adds nodes → consolidation reclaims.

### Next

*Queued and build-now — near-term build order.*

#### Observability

- [#629](https://github.com/asanexample/platform/issues/629) **Epic: single pane of glass — multi-cluster, all signals.** **Collection + read-federation DONE** — the Gateway-native spoke edge is replicated across every store and one Grafana spans platform + preprod, broken out by `cluster`, with correlation intact:
  - [#626](https://github.com/asanexample/platform/issues/626) Mimir federation + multi-cluster dashboards ✅ · [#627](https://github.com/asanexample/platform/issues/627) Logs spoke ✅ · [#628](https://github.com/asanexample/platform/issues/628) Traces spoke ✅ · profiles spoke ✅ (#637) · uniform `cluster` label ✅ ([#630](https://github.com/asanexample/platform/issues/630))
  - **Remaining = the access half: P13 per-team isolation ([#590](https://github.com/asanexample/platform/issues/590)) — DESIGNED + PAUSED.** Decision: re-tenant by team (hard boundary; Enterprise ruled out). Needs a read-side identity→tenant proxy (OSS Grafana has no per-user datasource gating). Phase 0 (collection) already satisfied — team signals flow tagged by namespace. **Resume at the Phase-2 read-proxy spike** (the crux). Full plan in the #590 design comment.

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

- **Cost guardrails — aggregate budgets + FinOps visibility** — Forward half of Cost & FinOps. Aggregate per-team budgets/caps (the quota-cap dial seam left by Phase 3), cost dashboards/FinOps visibility, anomaly alerts.

#### Reliability & Tech Debt

- [#769](https://github.com/asanexample/platform/issues/769) **Epic: tech-debt paydown — 2026 H2 inventory.** Deep 10-pass audit ([`docs/tech-debt-audit-2026-06-25.md`](docs/tech-debt-audit-2026-06-25.md), ~150 `TD-NNN` findings). Tier 1 (security/correctness, spot-verified): enforce cosign on the hub ([#770](https://github.com/asanexample/platform/issues/770)), private-only EKS default ([#771](https://github.com/asanexample/platform/issues/771)), fail-closed gate scripts ([#772](https://github.com/asanexample/platform/issues/772)), DeveloperAccess regression ([#647](https://github.com/asanexample/platform/issues/647)). Tier 2 (systemic): provider-constraint standardization ([#773](https://github.com/asanexample/platform/issues/773)), `.tool-versions` SSOT ([#774](https://github.com/asanexample/platform/issues/774)), Azure-carcass removal ([#775](https://github.com/asanexample/platform/issues/775)), Action SHA-pinning ([#776](https://github.com/asanexample/platform/issues/776)), Dependabot coverage ([#777](https://github.com/asanexample/platform/issues/777)), tests-into-PR-gates ([#778](https://github.com/asanexample/platform/issues/778)). Security/IAM findings fold into the existing tracker [#654](https://github.com/asanexample/platform/issues/654).

### Later

*On the map; not yet scheduled or blocked on a dependency (e.g. the planned rebuild).*

#### Network & Connectivity

- **Network hardening backlog** — Rollup -> filter label:area/network. Includes #162 WireGuard pod encryption, #163 node subnet sizing, #166 Kyverno HA hostNetwork, #206 subnet-router after scale-up.

#### Kubernetes & Ingress

- **Autoscaling** — Workload + cluster autoscaling as a paved-road capability (HPA/VPA/Karpenter-class), governed and surfaced through the platform abstractions.

#### Identity & Access

- **Identity & Access Strategy — north-star (design-of-record landed; Phase-1 build decomposed — epic [#884](https://github.com/asanexample/platform/issues/884), subs #885–#890).** The unified workforce-first model in [`docs/architecture/identity-and-access-strategy.md`](docs/architecture/identity-and-access-strategy.md): decide access once → derive → project into every system (AWS, apps, GitHub, PagerDuty, Slack) from one git source of truth (Teams + **People** + Grants); dangerous power borrowed temporarily (eligibility-in-git + timed activation); auth strength scaling with role; plus the honest scale-hardening (intent-vs-effected verification, decide/apply split, drift detection, meta-governance). **Phase 1 (highest value-per-effort) = the People roster + deriving AWS (Identity Center console) *and* Keycloak (app) access from it, retiring the hand-maintained HCL/seed-users so "add a person" is one PR.** (The per-team *cluster*-access regression [#647](https://github.com/asanexample/platform/issues/647) is a separate plane — resolved by OIDC-native cluster auth [#364](https://github.com/asanexample/platform/issues/364), not the Identity Center generator.) The ADR-068 P4 items below (#361–#368) realize the access-model core; the machine/agent plane defers to ADR-074 + the graduated-autonomy model ([ADR-086](docs/adrs/086-autonomous-agent-access.md), see Agentic Workloads). **CIAM (customer identity) is a named, deferred plane.**
- [#361](https://github.com/asanexample/platform/issues/361) P4 (ADR-068): Product-scoped & cross-team access model
- [#362](https://github.com/asanexample/platform/issues/362) P4.1 (ADR-068): AccessGrant CRD + cluster projection
- [#363](https://github.com/asanexample/platform/issues/363) P4.2 (ADR-068): Access-model-as-code — Product roles in Keycloak
- [#364](https://github.com/asanexample/platform/issues/364) P4.3 (ADR-068): OIDC-native developer cluster auth (EKS OIDC IdP)
- [#365](https://github.com/asanexample/platform/issues/365) P4.4 (ADR-068): Fan-out — ArgoCD RBAC + Backstage permissions from product roles
- [#367](https://github.com/asanexample/platform/issues/367) P4.6 (ADR-068): team-admin governance + grant lifecycle (request/TTL/re-attest)
- [#368](https://github.com/asanexample/platform/issues/368) P4.7 (ADR-068): Two-plane grant enforcement (access-grant-gate CI + Kyverno)
- **East-west zero-trust mTLS / service identity** — Decided (ADR-057), not yet built. Service identity + east-west mTLS zero-trust between workloads.

#### Governance & Supply-chain

- **Kyverno policy backlog** — Rollup -> filter label:area/policy. Includes #77 CEL ValidatingPolicy, #78 PolicyException governance, #79 HIPAA/PCI packs, #80 kyverno-json, #81 multi-cluster distribution, #82 nodeSelector validation, #93 PolicyReport observability.
- **Security & hardening backlog** — Rollup -> filter label:security. Includes #59 _v1 rename, #70 prod least-privilege, #111 ArgoCD GitHub App, #118 customer KMS CMKs, #129 SCA/AppSec, #132 CSPM, #149 Falco, #152 state-bootstrap S3, #196 Backstage ns hardening, #213 token rotation, #242 EBS orphans, #243 chart-repo resilience, #273 CoreDNS.

#### GitOps & Delivery

- [#500](https://github.com/asanexample/platform/issues/500) P2.4 (ADR-056): progressive delivery for prod — Argo Rollouts

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

### Identity & Access

- **EKS Pod Identity for workload AWS access** — Shipped. Pod Identity associations replace IRSA annotations for environment workloads. ADR-041/047.
- **Keycloak IdP + OIDC consolidation (Dex/oauth2-proxy retired)** — Shipped. Keycloak as IdP-of-record, OIDC for ArgoCD+Backstage, retired Dex+oauth2-proxy. ADR-052/053/059.
- **Per-team developer RBAC + platform-engineer access model** — Shipped. DeveloperAccess-<team> namespace-scoped RBAC; PlatformAdmin operate-not-author. ADR-039/040.

### Governance & Supply-chain

- **Compliance-tier model + SOPS-encrypted config secrets** — Shipped. standard/pci/hipaa tiers drive config; SOPS/KMS committed secrets. ADR-013/055/066.
- **Keyless cosign signing + SBOM + SLSA L3 provenance** — Shipped. cosign keyless signatures, CycloneDX SBOM, SLSA Build L3 provenance, verify at admission. ADR-042/050.
- **Kyverno admission engine + Audit→Enforce rollout** — Shipped. Kyverno HA engine + ClusterPolicies, phased Audit→Enforce on preprod+platform. ADR-014.
- **Per-product image scoping + supply-chain split** — Shipped. Kyverno restrict-images per Product registry; platform-owned cosign verify vs product-owned restrict (ADR-067). Includes ECR cross-account container registry (ADR-028).
- **Secrets management: External Secrets Operator + Secrets Manager** — Shipped. ESO + ClusterSecretStore sync from AWS Secrets Manager/SSM; secret naming convention + cross-account secret isolation. ADR-019/024/025/026.

### GitOps & Delivery

- **ApplicationSets + PR preview environments** — Shipped. ApplicationSet generators; PR-preview ephemeral deployments. ADR-032.
- **ArgoCD GitOps + per-team AppProjects/RBAC** — Shipped. ArgoCD delivery engine, per-team AppProjects, SSO RBAC. ADR-021.
- **Multi-stage promotion: auto ≤ staging + gated prod** — Shipped (P2). Promote-by-digest, auto-promote reconciler ≤ staging, gated prod. ADR-067 P2 / #377.
- **Release-CRD digest promotion + Product-registry source-of-truth** — Shipped. Image-digest promotion via control plane (protected-main); Product registry + Environment claims drive delivery. ADR-069/071.

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

- **Falco runtime threat detection (preprod)** — Shipped. Falco eBPF runtime threat detection on preprod. ADR-045.
- **Prometheus/Grafana stack + Mimir durable metrics** — Shipped (P1+P2). kube-prometheus-stack + Grafana; Mimir S3-backed durable metrics via remote-write. ADR-043/044.

### Cost & FinOps

- **Per-environment ResourceQuota + cost-allocation tags** — Shipped baseline. Per-environment ResourceQuota; Team/Product/Stage cost-allocation tags on resources.

### Platform Tooling & Ops

- **Validated teardown→rebuild-from-scratch** — Shipped. Repeatable full teardown+rebuild (58/58) validated; runbook + platctl automation.
- **platctl CLI — bootstrap/teardown/validate** — Shipped. platctl: bootstrap, teardown, lockdown/unlock, validate, kubeconfig; DAG-aware. ADR-038.

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
