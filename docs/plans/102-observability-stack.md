# #102 — Observability stack (metrics, logs, traces, profiles, cost, cloud resources) — hub-and-spoke, phased

> **Status:** Design approved, implementation not started. Parked to do a small task first; resume at
> "Execution order". Tracking issue: [#102](https://github.com/asanexample/platform/issues/102).

## Context

Capability gap #7 (CNCF Platforms whitepaper): today only Hubble (network) + ArgoCD (deploy state) —
**no runtime metrics/logs/traces/cost**. Goal is a **single pane of glass** across all environments.
Deliver the **full** stack in **small, independently verifiable phases** (one sub-issue + Terragrunt
unit(s) each, gated `plan → apply`, verified before the next). Supersedes #93 (closed by the
policy-reporter phase).

## Topology — central hub on the platform cluster

- **Hub = platform cluster** (next to ArgoCD): central **Grafana + SSO** and the **multi-tenant storage
  backends** — **Mimir** (metrics), **Loki** (logs), **Tempo** (traces). One UI, one set of stores.
- **Spokes = each workload cluster** (platform-itself first, then preprod, later prod): lightweight
  **collectors** (Prometheus-agent / Grafana Alloy / OpenTelemetry Collector) that **remote-write / push**
  to the hub over **Tailscale / Transit Gateway**.
- **Tenancy spine:** tenant ID = team = `teams.hcl` key, stamped on the **write path** as `X-Scope-OrgID`
  from the namespace label `platform.refplat.org/tenant`, enforced **server-side** by `auth_enabled: true`,
  **pinned per-team on the read path** by Grafana datasources. `cluster`/`env` is an extra label. One model
  across every signal → the central Grafana isolates **per-team across clusters**.
- **Grafana is Tailscale-only:** exposed via the **platform** `gateway-config` (`internal = true`) at
  `grafana.aws.refplat.org` — not internet-facing.

## Locked decisions

- Full stack, phased; one sub-issue + unit(s) per phase; gated apply; verify each.
- **Deploy via Terragrunt units**; **hub on platform**; phase 1 dogfoods the platform cluster (no
  cross-cluster networking yet).
- **End-state = full per-team tenant isolation** via `X-Scope-OrgID`; built isolation-ready from day one
  (`auth_enabled: true`, tenant stamped from the namespace label).
- **Absolute latest stable versions** for every chart AND every provider/module pin — no betas/RCs.
- **HA is a per-unit toggle** — each module takes `high_availability` (bool), mirroring the existing
  **ArgoCD module** (`high_availability = false # sufficient for non-production`). `true` → distributed /
  RF3 / multi-replica / anti-affinity / PDB; `false` → monolithic / single-replica (cost-optimized).
  Default **off** on the small reference clusters; flip **on** per-unit for prod or capacity-rich clusters
  — same modules either way. Granular replica/resource/retention overrides remain separate variables.
- **Cost-conscious by design.** HA without waste: the big cost levers are **data volume** (retention +
  trace sampling + cardinality limits) and **compute** (Graviton/arm64, spot for stateless tiers, modest
  per-pod requests), not replica counts. Every replica/resource/retention value is a variable; scale on
  OpenCost evidence (the stack measures its own cost). See Cost section.
- Observability components are **platform add-ons → IRSA** (ADR-018); store S3 buckets are
  platform-account/platform-cluster (reuse `infra/modules/aws/s3/`).
- **OSS-default, commercial opt-in** (full design: **"Editions & commercial accommodation"** below). Every
  capability ships an OSS implementation as the default; commercial editions/backends (Grafana
  Enterprise/Cloud, AMP, Grafana SLO/Synthetics/OnCall) are **per-unit opt-in flags**, never a fork. We run
  100% OSS (no Enterprise budget); users may flip to commercial without re-authoring instrumentation,
  dashboards, or alerts. Each phase's module **must expose its commercial seam** even when only the OSS path
  is implemented first.

## Editions & commercial accommodation (OSS-default, commercial opt-in)

**Principle: separate the *capability* from the *implementation*.** Every capability has an OSS
implementation wired as the default; commercial editions/backends are a **per-unit opt-in flag**, not a
parallel codebase. Mirrors the existing `high_availability` toggle philosophy, extended to an
edition/backend dimension. We build and run 100% OSS (no Enterprise license budget); a downstream user with
budget can flip to commercial **without re-authoring** their instrumentation, dashboards, or alerts.

**Why it's feasible: the data plane speaks open standards.** OTLP, Prometheus remote-write,
PromQL/LogQL/TraceQL. *Where data lands and who renders it* is a config swap, not a re-architecture — so a
self-hosted Mimir backend and a managed AMP/Grafana-Cloud backend are interchangeable behind the same
write/query interface. The mandate is to **not break that portability** with backend-specific coupling.

### Capability → implementation matrix (every default is OSS)

| Capability | OSS default (we run this) | Commercial opt-in | Flag |
|---|---|---|---|
| Grafana edition | `grafana/grafana` OSS | `grafana-enterprise` + license secret, or Grafana Cloud | `grafana_edition` |
| Per-team isolation | per-team OSS instances / Dex | Enterprise `org_mapping` (single org + RBAC) | (via `grafana_edition`) |
| Metrics store | self-hosted **Mimir** | **AMP** / Grafana Cloud Metrics | `metrics_backend` |
| Logs / traces store | **Loki** / **Tempo** | Grafana Cloud Logs / Traces | `logs_backend` / `traces_backend` |
| SLOs / error budgets | **Sloth** or **Pyrra** (render rules) | Grafana SLO | `slo_engine` |
| Synthetics / uptime | **blackbox-exporter + k6** | Grafana Synthetic Monitoring | `synthetics_engine` |
| Paging / on-call | Alertmanager → SNS/email (+ optional OnCall-OSS¹) | Grafana OnCall Cloud / PagerDuty / Opsgenie | `oncall_provider` |
| Reporting / audit log | not wired (acknowledged OSS gap) | Enterprise reporting + audit | (via `grafana_edition`) |

Default profile = **all OSS, self-hosted**. A bundled `edition = "oss" | "enterprise" | "cloud"` profile can
set sensible commercial defaults across the board, or individual flags flip one capability at a time.

¹ **Grafana OnCall OSS is at-risk** — Grafana signaled it's winding the OSS edition down in favour of Cloud
IRM. Treat as optional; the safe default is Alertmanager → SNS, with PagerDuty/Opsgenie as the commercial
escalation seam.

### Portable layer (constant in both modes) vs. what swaps
- **Constant — authored once, never re-done to go commercial:** app instrumentation (OTel SDK / Beyla),
  collection (Alloy / OTel Collector), **dashboards-as-code** (JSON), **alert rules** (`PrometheusRule`),
  SLO *definitions* (abstract objective/window).
- **Swaps — config only:** backend endpoint + auth + tenant header; Grafana edition image + license secret;
  which engine *renders* the abstract SLO/synthetic definitions.

### Module contract
Each capability module expresses the capability in **backend-agnostic** terms and selects the
implementation internally — e.g. the `slo` module takes `{ objective = 99.9, window = "30d" }` and renders
**Sloth CRs** (`slo_engine = "sloth"`) or **Grafana SLO** resources (`"grafana_slo"`). Commercial-only paths
are simply **not wired** when OSS is selected (graceful degradation, no dangling refs). Commercial
license/SaaS credentials come via **External Secrets**, only when a commercial edition is chosen.

### Honest limits (stated, not papered over)
- A few commercial features have **no OSS parity** (Enterprise reporting/audit, advanced RBAC, Grafana Cloud
  adaptive metrics). For those the platform offers the **seam** (flag + integration point) and documents
  "OSS default = not available / lesser" — we accommodate by making it opt-in, never by blocking or faking.
- Going commercial **sidesteps AGPL** for that user (they hold an Enterprise license / use Cloud); see the
  AGPL note in security/compliance.
- The toggle trades **money for ops** — OSS = we operate 24/7 infra; commercial = pay to offload it — without
  touching the portable layer above. **OpenCost (P11)** is the evidence for which way is cheaper at our scale.

## Security model & hardening (LOAD-BEARING — the isolation depends on it)

1. **`X-Scope-OrgID` is a trust header, NOT auth.** Isolation holds only if untrusted parties can't set
   it. Therefore: **(a)** cross-cluster ingest endpoints are **authenticated** (mTLS or bearer token), not
   merely network-reachable; **(b)** the hub **overwrites** the tenant header from the *authenticated
   source identity* — never trust a client-supplied value; **(c)** the OTel collector derives tenant from
   the **verified pod namespace** (`k8sattributes`), overwriting any app-supplied tenant attribute.
2. **Network-isolate the raw store endpoints.** A `team-*` pod must not reach Mimir/Loki/Tempo
   distributor/query endpoints directly — only platform collectors and Grafana may. Give the
   `observability` namespace its own default-deny + explicit allows (defense-in-depth), and a tenant-side
   egress deny to the store services.
3. **Per-tenant limits = a security control** (noisy-neighbor / cross-tenant DoS). Set Mimir/Loki/Tempo
   per-tenant overrides (ingestion rate, series/cardinality, query limits) **when the stores land**
   (P2/P3), not only in the isolation phase.
4. **Grafana hardening** (crown-jewel — datasources to every tenant): lock the datasource proxy (SSRF
   class), disable unsigned plugins, least-privilege org roles, scope `Admins→GrafanaAdmin`, audit access
   for regulated tiers.
5. **Log/trace data governance** (HIPAA/PCI, ADR-013): redact secrets/PII at the collector; per-tier
   retention; KMS-encrypted buckets for regulated tiers (s3 module is AES256 today — extend for KMS).
6. **Secrets** via External Secrets from Secrets Manager (Grafana admin/OAuth, Dex, SAML cert, store
   creds) — nothing sensitive in Helm values or git.

## Architecture notes

- **Metrics store = Mimir** (monolithic, S3, multi-tenant) — the central store must receive multi-cluster
  remote-write and isolate per-team. P1 stands up kube-prometheus-stack (fast bundled win) scraping the
  hub; Mimir is added in P2 and the hub Prometheus gains `remote_write` to it (additive, no migration).
- **Charts** (deployment mode driven by the `high_availability` toggle): `kube-prometheus-stack`
  (Prometheus 1→×2, Alertmanager 1→×3) · `mimir-distributed` (monolithic→**distributed** RF3) · `loki`
  (SingleBinary→**SimpleScalable** RF3) · `tempo` (monolithic→**distributed** RF3) · `alloy` (DaemonSet;
  Promtail/Grafana-Agent EOL) · `opentelemetry-collector` (gateway, 1→×2) · `grafana`/`dex` (1→×2) ·
  `opencost`/`policy-reporter` (1→×2) · `pyroscope` (monolithic→microservices) · `opentelemetry-operator`
  + `beyla` (DaemonSet) · `blackbox-exporter` · `k6-operator` · `sloth`/`pyrra` · `yace`/`cloudwatch-exporter`.
  The module maps `high_availability` to the chart's mode + replica counts + PDB/anti-affinity.
- **Versioning policy (latest-stable):** at the START of each phase, resolve the **absolute latest stable
  (GA)** chart version via `helm search repo <repo>/<chart> --versions` (or ArtifactHub/OCI) and pin THAT
  in `helm_versions`; likewise bump the module/provider pins (`tofu`, `aws`, `helm`, `kubernetes`
  providers) to current stable. Record the resolved version in the phase's PR. No betas/RCs. Re-resolve
  per phase since these charts move fast (e.g. `kube-prometheus-stack` is already ~v86.x — well past the
  v77 in older docs). Apps are bundled by the chart; verify the bundled Grafana/Prometheus/Loki/Tempo/
  Mimir app versions are current GA too.
- **Module/unit pattern:** copy `infra/modules/external-secrets/` (helm_release + IRSA); register in
  `infra/live/aws/_versions.hcl`; units mirror external-secrets `terragrunt.hcl`. Per-team data as maps
  **at the unit** from `teams.hcl`; modules team-agnostic (`map(...)` + `for_each`).
- **Grafana state = dashboards-as-code** (provisioning ConfigMaps/sidecar, dashboards in-repo) +
  provisioned datasources → **stateless, HA-by-replication**: run ≥2 identical replicas each fully
  provisioned (no shared DB needed — every replica is interchangeable). RDS Postgres only if
  user-*created* state (ad-hoc dashboards, users) must persist — deferred unless required. Default sqlite
  is ephemeral, which is fine precisely because all config is declarative.
- **SSO:** Grafana OSS has no native SAML → **Dex** bridge (Identity Center SAML → OIDC) on the hub +
  Grafana `auth.generic_oauth`, reusing the ArgoCD pattern (`grafana_sso_url`/`grafana_sso_ca_data` in
  `secrets.hcl`). **Manual prereq:** create a Grafana SAML app in Identity Center.
- **Cross-cluster write path (P10):** spoke collectors reach hub ingest over **Tailscale / TGW**
  (preprod↔platform already connected), **authenticated** per the security model; isolate by source +
  overwrite tenant header.
- **HA / SPOF — "who observes the observer?":** the hub is HA *and* a single cluster — both matter.
  - **When `high_availability = true`:** every component multi-replica with **pod anti-affinity +
    topology spread across AZs + PodDisruptionBudgets**; storage backends (Mimir/Loki/Tempo) at
    **replication factor 3** so any one ingester/AZ can fail without data loss. Grafana ≥2 stateless
    replicas (above). Prometheus ×2 with store-side dedup (Mimir HA tracker via `cluster` + `__replica__`).
    Alertmanager ×3 gossip.
  - **Capacity / the toggle:** HA=true needs **≥3 schedulable nodes across ≥2–3 AZs** (RF3 + anti-affinity)
    or pods go Pending — so it's a per-unit choice, **off** on the small reference clusters and **on** for
    prod / capacity-rich clusters. When a specific cluster can't host full HA, leave the toggle off for
    that unit (an honest single-replica) rather than shipping a half-wired "HA". Size node groups + confirm
    AZ spread before flipping it on.
  - **Cross-cluster resilience:** **agent-side buffering** (remote-write WAL) so spokes don't lose data
    during hub outages; keep each cluster's local Prometheus for last-resort local debugging when the hub
    is unreachable.

## Cost-efficiency (reconciled with HA)

The biggest spend in an observability stack is **data volume** and **idle compute**, not replica count —
so HA and frugality coexist if we attack volume and compute directly:

- **Data volume (the #1 lever):**
  - **Trace sampling** — tail-sampling in the OTel collector (keep errors/slow traces, sample the rest);
    typically cuts trace storage 90%+. Single biggest saver.
  - **Retention discipline** — short defaults (metrics ~30d, logs ~14d, traces ~7d), all variables; long
    tails go to cheaper tiers, not hot storage.
  - **Cardinality limits** — drop noisy/high-cardinality labels at scrape; enforce per-tenant series
    limits (doubles as the noisy-neighbor security control). High cardinality = Mimir memory + S3 = $.
  - **S3 lifecycle** — extend `infra/modules/aws/s3/` with lifecycle rules (transition old chunks/blocks
    to S3-IA/Glacier, expire past retention). Object storage is the cheap tier — keep only WAL on gp3.
- **Compute:**
  - **Graviton (arm64)** node group for the stack (~20% cheaper; all these charts ship arm64 images).
  - **Spot** for stateless tiers only (queriers, query-frontend, distributors, OTel gateway, Grafana) —
    NOT ingesters/stores holding un-flushed data.
  - **Modest per-pod requests** + VPA/HPA where safe; HA = more replicas but each one small.
- **HA↔cost trade-offs to make explicitly:**
  - **RF3 + AZ-spread incurs cross-AZ data-transfer $.** Accept it for the durability-critical ingest
    path; for everything else prefer same-AZ. Compress remote-write (snappy). Note the cross-cluster
    remote-write (preprod→platform) transfer cost — OpenCost will quantify it.
  - **Baseline always-on cost:** the hub stack runs 24/7 (you can't scale it to zero like the overnight
    node-group scale-down, since it's the thing doing the observing). With `high_availability=false` on
    the reference clusters the baseline is single-replica + modest — HA's multiplied footprint (and its
    cross-AZ transfer $) is opt-in for prod. Spokes' agents disappear when a spoke scales down — fine.
- **Self-hosted vs managed:** self-hosting LGTM (chosen) gives control and avoids per-sample managed fees,
  but is 24/7 infra. AMP/AMG (managed) trade ops for usage-based pricing — noted as an alternative if the
  reference footprint proves more expensive than managed at this scale. **OpenCost (P11) is the feedback
  loop** that tells us which way is cheaper.

## Constraints (per cluster they apply to)

1. **Kyverno** `exclude_namespaces += observability` on each cluster running the stack (platform in P1,
   preprod in P10). `infra/modules/policy/variables.tf` / unit override.
2. **Tenant `default-deny-ingress`** blocks a collector scraping `team-*` pods → add `allow-metrics-scrape`
   ingress (from `observability` ns) to the **tenant module**; only on clusters with tenants → **preprod
   (P10)**.
3. **`observability` namespace** created WITHOUT PSA-`restricted` enforce (node-exporter hostNetwork) and
   without the tenant label — not via the tenant module. (But DO give it a default-deny per security #2.)
4. **Grafana group→org mapping** is Enterprise-only → isolation phase defaults to **per-team Grafana
   instances (OSS)**, Enterprise `org_mapping` as a one-flag upgrade. Identity Center emits group **GUIDs**
   → key on GUIDs, like ArgoCD's `rbac_policy_csv`.

## Phases (each = one sub-issue + gated apply)

Grouped into tracks; numbering is the dependency-ordered execution sequence. Tracks A–B are the
foundation; C delivers the "cloud resource" half of the goal; D–E are the developer-experience / reliability
depth; F–G are multi-cluster reach, economics, and tenant self-service. Each phase is still one
independently-verifiable sub-issue + unit(s); do not batch.

### Track A — Core stores & UI
- **P1 — Hub: Grafana + SSO + metrics (dogfood platform).** kube-prometheus-stack + Dex SSO;
  `observability` ns (+ default-deny) + Kyverno exclude on platform; **dashboards-as-code** (concrete set:
  see **"P1 dashboard inventory"** below) + Grafana hardening (#4); expose Grafana Tailscale-only.
  **Bundled alert rules on** (mixins), with the EKS-absent rule groups disabled + a **minimal critical-only
  route** (Alertmanager → one SNS topic → email) + a **Watchdog** heartbeat — so the platform cluster isn't
  un-alerted while later phases land (see **"P4 alert inventory"**). **Verify:** SSO login; Platform Health
  overview + ArgoCD / Kyverno / Cilium / API-server / node dashboards populated; a forced test alert reaches
  email and Watchdog is steady.
- **P2 — Hub: Mimir (multi-tenant metrics store).** Mimir monolithic + S3 + IRSA, `auth_enabled` +
  **per-tenant limits** + store-endpoint network isolation; hub Prometheus `remote_write` → Mimir (tenant
  `_platform`); Grafana datasource → Mimir. **Verify:** platform metrics served from Mimir; a forged
  `X-Scope-OrgID` from a tenant-side pod is network-denied.
- **P3 — Hub: Loki + Tempo (multi-tenant).** Loki SingleBinary + Tempo monolithic, S3 + IRSA,
  `auth_enabled` + per-tenant limits + isolation + **collector-side redaction**; hub Alloy + OTel write
  platform telemetry (tenant `_platform`); datasources + trace→logs correlation. **Verify:** platform
  logs/traces in Grafana. (Splittable P3a/P3b.)

### Track B — Make it actionable
- **P4 — Alerting, notifications & incident response (full set).** Promote P1's minimal route to the full
  design (see **"P4 alert inventory"**): Mimir **ruler** (multi-tenant alert rules) + curated
  platform-specific `PrometheusRule`s + severity routing + inhibition + runbook links; Alertmanager → SNS →
  email/Slack/PagerDuty, escalation via `oncall_provider`. Plus the incident-response glue: **Kubernetes
  events → Loki** (event-exporter / Alloy) and **deploy/change annotations** on dashboards (correlate a
  regression with the ArgoCD sync that caused it). **Verify:** a test alert fires end-to-end at each
  severity; inhibition + Watchdog confirmed; a deploy shows as a dashboard annotation.

### Track C — Cloud-resource observability (AWS)
- **P5 — Cloud-resource observability.** The "cloud resource" half of the goal — visibility *beyond* the
  cluster. **(a)** Grafana **CloudWatch datasource** (zero-storage, query-time) for broad coverage of RDS /
  ALB·NLB / SQS·SNS / Transit Gateway / Route53 / ACM / NAT / EKS control plane; **(b)** **YACE /
  cloudwatch-exporter → Mimir** (IRSA) for the subset we alert + dashboard on in PromQL; **(c)** **CloudWatch
  Logs → Loki** (Firehose / Alloy `loki.source.awsfirehose`) for RDS / ALB / VPC-flow logs + the existing
  **CloudTrail**. Dashboards for the AWS resources backing platform + tenants. **Verify:** RDS/ALB metrics +
  a VPC-flow/CloudTrail query in Grafana; one cloud-resource alert (e.g. RDS free-storage low) fires. (Cloud
  *cost* lands in P11.)

### Track D — Developer experience / APM
- **P6 — APM correlation (RED + service graph + exemplars).** Turn Tempo from a trace bucket into APM:
  enable the Tempo **metrics-generator** → auto **RED metrics** + **service graph** into Mimir; wire
  **exemplars** (Prometheus/Mimir) so a latency spike links to the exact trace; complete the
  **metrics ↔ traces ↔ logs** correlation (P3 did trace→logs). **Verify:** click a latency spike → exemplar
  → trace → logs, and a service map renders for the hub's own components.
- **P7 — Zero-code auto-instrumentation.** **OpenTelemetry Operator** (annotation-driven SDK auto-inject:
  Java/Python/Node/.NET/Go) + **Grafana Beyla** (eBPF — RED metrics + traces with no app changes). Makes
  per-app onboarding free instead of per-team hand-instrumentation; dogfood on a hub workload + a canary,
  then it's the default tenants get at P10. **Verify:** an un-instrumented sample workload emits RED metrics
  + traces with zero code change.
- **P8 — Continuous profiling (Pyroscope).** **Pyroscope** store (S3 + IRSA, `auth_enabled` + per-tenant
  limits, `high_availability` toggle) + Alloy/SDK profiling; Grafana **traces ↔ profiles** link (flame graph
  from a slow span). **Verify:** CPU/heap flame graphs for the hub's own components; jump from a trace to its
  profile.

### Track E — Reliability
- **P9 — SLOs & synthetics.** External truth + reliability targets: **blackbox-exporter** (HTTP/TLS/latency
  probes of HTTPRoutes from *outside*) + **k6** scripted checks → Mimir; **Sloth/Pyrra** render SLO
  recording + multi-window burn-rate **error-budget** alerts from abstract `{ objective, window }`
  definitions (`slo_engine` flag). **Verify:** an external probe catches a synthetic outage the internal
  metrics miss; an SLO burn-rate alert fires against a forced error budget.

### Track F — Multi-cluster reach & economics
- **P10 — Onboard preprod spoke (all signals).** Preprod foundations (Kyverno exclude + tenant
  `allow-metrics-scrape` + `observability` ns) + **authenticated** cross-cluster ingest (Tailscale/TGW,
  per security #1) + agent buffering. Preprod collectors stamp `X-Scope-OrgID=<team>` + `cluster=preprod`;
  instrument app-alpha — now largely **free via P7 auto-instrumentation** (metrics + traces) plus structured
  logs. **Verify:** central Grafana shows preprod `team-alpha` metrics/logs/traces/profiles under tenant
  `alpha`.
- **P11 — Cost (in-cluster + cloud).** **OpenCost** per cluster → cost metrics into Mimir
  (per-team/namespace/cluster + cross-cluster-transfer dashboards); plus **AWS CUR → Athena → Grafana**
  (Athena datasource) for true cloud spend beyond the cluster, attributed by the `Team` tag. **Verify:**
  per-namespace cost across clusters AND cloud-resource cost by team in one pane. Feeds the
  self-hosted-vs-managed call.
- **P12 — Policy reporting (closes #93).** `policy-reporter` on each Kyverno cluster, metrics into Mimir;
  central Grafana dashboards (violations by tenant/policy/severity, Enforce vs Audit, verifyImages).
  **Verify:** dashboards populated. **Close #93.**

### Track G — Tenancy & self-service
- **P13 — Full per-team tenant isolation.** Per-team Grafana access (per-team OSS instances or Enterprise
  `org_mapping`); datasources pinned to the team's `X-Scope-OrgID`; IC group-GUID gating; `teams.hcl`
  `observability` block + maps. Applies across **all** signals — metrics, logs, traces, profiles.
  **Verify (money shot):** alpha dev sees only alpha's telemetry; bravo query AND a forged-header write are
  both denied — across all signals and clusters.
- **P14 — Self-service & golden path.** Make observability a paved road, not a ticket: per-team
  dashboards/alerts/SLOs **auto-provisioned** from the `teams.hcl` `observability` block; documented app-repo
  conventions (`ServiceMonitor`/`PodMonitor`/OTLP/profiling labels); a **Backstage** tie-in (#103/#104) so a
  service's dashboards/logs/traces/profiles are one click from its catalog entry. **Verify:** a new team
  added to `teams.hcl` gets a working dashboard set + SLO + alert routing with no bespoke wiring.

## P1 dashboard inventory (concrete)

All dashboards are provisioned **as-code** via the kube-prometheus-stack Grafana **dashboard sidecar**
(a `ConfigMap` labelled `grafana_dashboard: "1"`), so they live in git and ship with the unit. Three tiers
by effort: **bundled** (ship with the chart), **vendored** (commit upstream JSON to
`infra/modules/<obs>/dashboards/`), **custom** (authored in-repo).

### Tier 1 — Bundled (kube-prometheus-stack, auto-provisioned — zero effort)
Genuinely useful day one:
- **Compute Resources** — Cluster / Namespace (Pods) / Namespace (Workloads) / Node (Pods) / Pod / Workload
- **Node Exporter** — Nodes + USE Method (Node & Cluster): CPU / mem / disk / network saturation
- **Kubernetes / API server** — request rate, latency, error ratio, SLO burn
- **Kubernetes / Kubelet** — per-node kubelet + cAdvisor
- **CoreDNS** — query rate / latency / errors
- **Prometheus / Overview** + **Alertmanager / Overview** — observe the observer

> **EKS accuracy note — turn OFF the unreachable scrape jobs so we don't ship dead dashboards / false
> "target down" alerts.** EKS runs a **managed control plane**: `kube-scheduler`,
> `kube-controller-manager`, and `etcd` metrics are **not scrapeable** and those bundled dashboards stay
> empty. Set `kubeScheduler.enabled=false`, `kubeControllerManager.enabled=false`, `kubeEtcd.enabled=false`
> in the chart values. Also `kubeProxy.enabled=false` — Cilium `kubeProxyReplacement=true` means there's no
> kube-proxy. On EKS, "control-plane visibility" = the **API server** dashboard (CloudWatch control-plane
> logs are a later, separate add-on).

### Tier 2 — Vendored upstream (commit pinned JSON; provision via sidecar)
The platform-specific dashboards P1 calls out — **none are chart-bundled**; each needs its component's
metrics enabled (ServiceMonitor / `prometheus.enabled`). Resolve the exact grafana.com **ID + revision**
at authoring time and commit that JSON (don't live-import by ID — upgrades go through PR review; re-point
hard-coded `datasource` fields to the provisioned Prometheus/Mimir uid):
- **ArgoCD** — official dashboard (argoproj `argo-cd` repo; grafana.com ~**14584**): app health, sync
  status, reconciliation rate, controller queue depth. Needs the ArgoCD metrics ServiceMonitors.
- **Kyverno** — official dashboards (kyverno repo): admission request rate + **allow/deny by policy**,
  policy execution latency, webhook health. (Richer per-tenant / severity / verifyImages PolicyReport
  views arrive in **P12** with policy-reporter — don't duplicate them here.)
- **Cilium Agent** + **Cilium Operator** + **Hubble** (cilium repo; grafana.com ~**16611 / 16612 / 16613**):
  datapath/BPF, **drops by reason/identity**, policy verdicts, endpoint health, Envoy/Gateway L7. Needs
  Cilium `prometheus.enabled` + Hubble metrics — ties directly to the "monitor drops first" debug habit.
- **cert-manager** (grafana.com ~**11001**): cert expiry countdown, renewal success/failure, ACME order
  errors — guards the Gateway TLS + Let's Encrypt DNS-01 path.
- **External Secrets Operator** (official ESO dashboard): sync success/failure, provider latency — guards
  the Secrets-Manager → K8s path the whole platform depends on.
- *(optional)* **external-dns** and **Tailscale operator** once we confirm they expose useful series.

### Tier 3 — Custom: "Platform Health" overview (the only authored dashboard in P1)
A single-pane **landing dashboard** — the first thing you open — aggregating the highest-signal panels
across the stack, each linking down into the tier-1/2 dashboards:
- **Cluster vitals:** nodes Ready/total, node CPU·mem·disk pressure, pods Pending / CrashLoopBackOff,
  recent OOMKills.
- **Control plane:** API server availability + p99 latency + error ratio (the one control-plane signal EKS
  exposes).
- **GitOps:** ArgoCD apps Synced/Healthy vs OutOfSync/Degraded.
- **Admission/policy:** Kyverno allow vs **deny** rate + webhook latency (catch a policy blocking deploys).
- **Network:** Cilium drop rate by reason + Hubble flow errors.
- **Certs/secrets:** soonest cert-manager expiry; ESO sync failures.
- **Capacity headroom:** cluster CPU/mem requests-vs-allocatable — the "about to fail scheduling" gauge,
  which is also the gate for flipping `high_availability=true` on a cluster later.

These overview panels are deliberately the same signals **P4** later promotes to alerts — author once, reuse.

## P4 alert inventory (concrete)

Alerts as-code: bundled rules ship with the chart; curated rules are `PrometheusRule` CRs in
`infra/modules/<obs>/alerts/` (multi-tenant via the Mimir **ruler** once P2 lands; in-cluster Prometheus
rules until then). Routing/silences live in Alertmanager config (secrets via External Secrets). Severity:
`critical` → page, `warning` → Slack/email, `info` → dashboard-only / inhibited. Every curated alert carries
a `runbook_url`. **Minimal critical-only route ships in P1; the full set lands in P4.**

### Tier 1 — Bundled (kube-prometheus-stack mixins — free, on in P1)
kubernetes-mixin + node-exporter mixin: `KubePodCrashLooping`, `KubePodNotReady`,
`KubeDeploymentReplicasMismatch`, `KubeStatefulSetReplicasMismatch`, `KubeJobFailed`, `KubeHpaMaxedOut`,
`KubeNodeNotReady`/`KubeNodeUnreachable`, `KubeletTooManyPods`, `KubeQuotaAlmostFull`,
`KubeCPUOvercommit`/`KubeMemoryOvercommit`, `NodeFilesystemAlmostOutOfSpace`/`…SpaceFillingUp`,
`NodeMemoryHighUtilization`, `KubeAPIErrorBudgetBurn` (multi-window SLO), `KubeClientCertificateExpiration`,
`KubeAPIDown`, `KubeletDown`, plus Prometheus self (`PrometheusTargetMissing`, `PrometheusRuleFailures`,
`PrometheusRemoteWriteBehind` — matters once spokes remote-write).

> **EKS — disable the rule groups for absent targets** or they fire forever: scheduler,
> controller-manager, etcd (`defaultRules.disabled` for `kubeSchedulerAlerting`,
> `kubeControllerManagerAlerting`, `etcd`) + kube-proxy (Cilium replaces it). Same root cause as the
> empty-dashboard note above.

### Tier 2 — Curated platform-specific (`PrometheusRule`, authored in P4)
The high-signal alerts the mixins don't cover — one rule file per component:
- **ArgoCD** — `ArgoCDAppDegraded` / `ArgoCDAppOutOfSync` (>15m), `ArgoCDAppSyncFailed`,
  `ArgoCDComponentDown` (repo-server / app-controller). *Deploy regressions.*
- **Kyverno** — `KyvernoWebhookDown` (admission unavailable = blocks/fails all admission),
  `KyvernoAdmissionDenySpike` (deny-rate jump → a policy is silently blocking deploys),
  `KyvernoReportsControllerDown`, policy-execution error rate. *Guards the admission path.*
- **Cilium** — `CiliumAgentDown` (no networking on that node), `CiliumOperatorDown`, `CiliumDropRateHigh`
  (drops by reason/identity), `HubbleDown`, `CiliumEndpointsNotReady`. *Network plane.*
- **cert-manager** — `CertExpiringSoon` (<21d warn / <7d crit), `CertNotReady`, `ACMEOrderErrors`.
  *Gateway TLS + Let's Encrypt won't silently lapse.*
- **External Secrets** — `ExternalSecretSyncFailing` (ES not Ready / SecretSyncError),
  `ClusterSecretStoreNotReady`. *The Secrets-Manager → K8s path everything depends on.*
- **Tailscale** *(optional)* — subnet-router / operator down (internal Gateway is Tailscale-only, so this =
  internal services unreachable).
- **Stores (from P2/P3)** — Mimir/Loki/Tempo ingester/compactor down, S3 write failures, per-tenant limit
  rejections (also the noisy-neighbor security signal, security §3).

### Tier 3 — Meta & routing design
- **Watchdog / DeadMansSwitch** — an always-firing alert routed to an **external** heartbeat
  (healthchecks.io / PagerDuty heartbeat). If it stops arriving, the *monitoring pipeline itself* is down.
  Ships in P1.
- **Severity routing** — `critical` → PagerDuty/OnCall page, `warning` → Slack, `info` →
  inhibited/dashboard; per-team routing keys arrive with isolation (P13).
- **Inhibition** — node-down suppresses that node's pod alerts; API/cluster-down suppresses the rest; a
  Kyverno-webhook-down inhibits the deny-spike noise it causes.
- **Maintenance windows / silences** — documented flow (later, auto-silence around ArgoCD syncs).
- **Runbooks** — every curated alert links a `runbook_url` (in-repo `docs/runbooks/`) so a page is
  actionable — mirrors the existing kyverno-break-glass runbook pattern.

This set intentionally mirrors the Tier-3 "Platform Health" dashboard panels — the same signals, now
actionable.

## teams.hcl extension (P13–P14)

Optional per-team block (`observability = { enabled, retention }`), everything else derived; derived
`observability_teams`; unit builds `tenant_id_map`/`grafana_hostname_map`/`tenant_group_map` (GUIDs).
Module stays team-agnostic.

## Testing & verification

- **Terratest** per new module, **plan-only / skipped** (helm-release modules can't be safely
  apply/destroyed in CI — matches the project's testing convention).
- Per-phase: own PR with `tofu fmt`/`validate`, gated `terragrunt plan → apply`, and a concrete runtime
  check (Grafana query / curl) before its sub-issue closes. Final isolation **negative test** (cross-team
  read denied + forged-header write denied) mirrors the ADR-039 and #64 "money shots".

## Execution order (resume here)

1. **Create the sub-issues first** (user's explicit ask): #102 → epic with a phase checklist; P1–P14
   sub-issues (tracks A–G) with scope + acceptance criteria (incl. the security invariants); link them; mark
   #93 superseded-by-P12.
2. **Implement P1** (own branch/PR; gated apply on platform; verify SSO + dashboards). Continue
   phase-by-phase in later turns; do not batch.

> **Sequencing note:** Tracks A→B→C are the must-have spine (stores → actionable → cloud resources). Track
> D (APM/auto-instrument/profiling) is deliberately *before* the preprod spoke (P10) so apps inherit
> zero-code instrumentation on onboard; if capacity or time is tight, D/E can slip after P10 without
> breaking dependencies — the only hard ordering is A → (B,C,D,E all depend on the P2/P3 stores) → P10 spoke
> → P11–P14.

## Out of scope / follow-ups

- Onboard **prod** as a spoke once it exists; **mTLS** everywhere on the ingest path (P10 starts with
  authenticated bearer/Tailscale, not full mTLS).
- **Grafana frontend RUM** (Faro) and **browser-journey synthetics** beyond P9's k6 HTTP/blackbox checks.
- **Cost Explorer** native dashboards beyond the P11 CUR→Athena path.
- Extend the `s3` module with **lifecycle rules + KMS** (retention currently in-app; AES256 today).

*(Previously out-of-scope, now folded into phases: AWS cloud-cost via CUR→Athena → **P11**; Grafana
Enterprise org-per-team → the **OSS-default/commercial opt-in** seam (Editions section) + **P13**.)*
