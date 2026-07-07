# Learn: Observability — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
live (as of this writing).

## Pinned versions (`infra/live/aws/_versions.hcl`, `helm_versions.*`)

| Component | Chart | | Component | Chart |
| --- | --- | --- | --- | --- |
| kube-prometheus-stack (Prometheus/Grafana/Alertmanager) | 87.5.0 | | Beyla (eBPF RED+traces) | 1.16.8 |
| Mimir (metrics) | 6.0.6 | | OTel Collector | 0.158.2 |
| Loki (logs) | 7.0.0 | | Sloth (SLOs) | 0.16.0 |
| Tempo (traces) | 2.25.5 | | OpenCost | 2.5.23 |
| Pyroscope (profiles) | 2.1.0 | | cortex-tenant | 0.8.1 |
| Alloy (collector) | 1.10.0 | | blackbox / policy-reporter / cloudwatch-exporter | 11.13.0 / 3.7.4 / 0.46.0 |

tenant-proxy is a **bespoke signed image**, digest-pinned in the live unit (ADR-071), not a chart. All live
in namespace `observability` (backends on the hub; OTel Operator in `opentelemetry-operator-system`).

## The stack ([ADR-043](../../adrs/043-self-hosted-observability-stack.md)/[044](../../adrs/044-mimir-durable-multi-tenant-metrics.md))

- **LGTM+P**: Loki · Grafana · Tempo · Mimir · **P**yroscope. Each is a specialist store for one signal
  shape; all share the storage pattern: small hot buffer on a gp3 PVC + durable blocks on **S3** (one bucket
  per signal, SSE-S3/AES256 explicit — the org SCP denies PutObject without the header; S3 via **Pod
  Identity**, ADR-047).
- **Metrics = additive:** Prometheus is the *scraper* (~15d local); it **remote-writes every sample to Mimir**
  (durable, S3). Grafana's default datasource is Mimir → rebuilding Prometheus loses nothing.
- **Mimir over Thanos:** first-class `X-Scope-OrgID` multi-tenancy (the spine hub-and-spoke needs). Classic
  microservices arch (distributor→ingester, RF1 on the reference cluster; `high_availability` toggles RF3).
- **Grafana:** the single pane; **SSO via Keycloak OIDC** (`platform-admins`→Admin, else Viewer);
  Tailscale-only (internal NLB); hardened (anon off, no signup). Datasources provisioned as code, named
  `<Store> (<tenant>)`, incl. federated `<Store> (all clusters)` and `Mimir (my team)` (the tenant-proxy lane).
- **Why self-hosted** (vs Datadog/Grafana Cloud/AMP-AMG): SaaS/managed pricing is per-host/series or
  per-sample — grows with cardinality (what a multi-tenant platform generates); self-hosted = compute you
  already run plus cheap S3, data stays in-account, dashboards-as-code, portable. Accepted trade: "we operate it."

## Tenancy — `X-Scope-OrgID`

- The header names a **tenant**; the store trusts it (**not authentication** — ADR-044). **Real isolation =
  network:** `observability` namespace is default-deny; stores are **ClusterIP-only**, never on the Gateway.
- **Cluster tenants** (LIVE, carrying data): `platform`, `preprod`. Spokes remote-write over a **write-only**
  Gateway HTTPRoute that **force-stamps** `X-Scope-OrgID` (a spoke can't spoof another tenant).
- **Per-team tenants** (the P13 split): a **write-path** proxy (`cortex-tenant`) relabels series to
  `<team>` for env namespaces → real `alpha`/`bravo` Mimir tenants (verified S3 blocks). **LIVE + exercised.**
  A **read-path** proxy (`tenant-proxy`) verifies the user's OIDC token, maps `groups`→tenant, fail-closed →
  the `Mimir (my team)` datasource. **Deployed + fail-closed but UNEXERCISED** — nothing points at it; per-team
  *visibility* is delivered by namespace-filtered dashboards instead. (See status below.)

## Collection & the instrumentation ladder ([ADR-077](../../adrs/077-application-instrumentation-strategy.md))

**Platform-injected** — apps carry no telemetry config; the platform stands up collectors + instruments.

| Signal | Collector (deploy) | → Backend |
| --- | --- | --- |
| Logs | Alloy DaemonSet (node-local `/var/log/pods`) | Loki |
| K8s events | Alloy **singleton** (dedup) | Loki |
| Profiles | Alloy eBPF DaemonSet (privileged, CPU sampler) | Pyroscope |
| **RED metrics + traces** | **Beyla** eBPF DaemonSet (kernel uprobes) | Mimir (scrape) + Tempo (OTLP) |
| Cluster/infra metrics | Prometheus (hub full / spoke **agent-mode**) + KSM + node-exporter | Mimir (remote-write) |
| App traces (opt-in) | OTel Collector (gateway) ← SDK | Tempo |
| AWS metrics | cloudwatch-exporter (YACE, tag-discovery) | Mimir |
| Synthetic | blackbox (`Probe` CR) · k6 (CronJob) | Mimir |
| Network flows | Cilium + Hubble (`ServiceMonitor`; chart's own off) | Mimir (+ standalone Hubble UI) |

**Ladder:** L0 **Beyla eBPF** (zero-code RED/traces/service-graph, every workload — **LIVE**) → L1 **OTel SDK
inject** (annotation `instrumentation.opentelemetry.io/inject-<lang>` → operator injects SDK + OTLP endpoint;
operator **LIVE** but **no `Instrumentation` CR wired to a workload yet**, P14) → L2 **agent-obs** (below).
Beyla replaces Tempo's metrics-generator as the RED source (ADR-077 D5).

## Correlation (all live)

Metric **exemplar** → **trace** (Tempo) → **logs** (Loki, via trace_id) → **profile** (Pyroscope, via aligned
`service.name`) — one click each. Plus service-graph + deploy annotations. Wired in datasource config
(`exemplarTraceIdDestinations`, `tracesToLogsV2`, `tracesToProfilesV2`).

## Act: SLOs · alerting · cost

- **SLOs:** **Sloth** (`PrometheusServiceLevel` → SLI recording rules + **multi-window burn-rate** alerts).
  Live: an API-server 99.9% SLO. **Per-prod-app SLOs auto-derived** from `gitops/environments/**/prod.yaml`
  (99.9% HTTP success off Beyla RED), evaluated in the Mimir ruler — feeds the ADR-056 canary error-budget
  freeze gate.
- **Alerting:** ~40 curated PrometheusRules (`observability/alerts/curated.yaml`); Alertmanager routes by
  `severity` (critical → PagerDuty + Slack + SNS; warning → Slack; inhibit critical→warning); a **dead-man's
  switch** (Healthchecks.io) pages if the pipeline goes silent. **Owner-routing** ([ADR-084](../../adrs/084-platform-identity-directory-and-owner-resolution.md)):
  the triage agent resolves the culprit's **team** from the git registries, pages that team's on-call,
  @-mentions the commit author in Slack.
- **Cost** ([ADR-091](../../adrs/091-cost-guardrails.md)): **OpenCost** (in-cluster allocation per team/ns,
  near-real-time "speedometer") + **true-cost-exporter** (AWS CUR→Athena, real unblended bill, "odometer";
  #668 — panels aggregate `max` not `sum` to avoid double-counting the monthly gauge). Budget enforcer (Kyverno
  gate on over-budget provisioning; ADR-091 Phase C, audit-first fail-open).

## Agent observability ([ADR-076](../../adrs/076-agent-observability.md)) — LIVE

OTel **GenAI semantic conventions**; "instrument once, fan out per consumer": **metrics** (`gen_ai_client_token_usage`,
`_operation_duration`, `triage_disposition_total`) scraped → Mimir; **traces** (`invoke_agent`→`chat`→
`execute_tool` spans + `gen_ai.*` attrs) → Tempo; **eval** (`triage_feedback_total{verdict}` human verdict).
Cost **derived** (tokens × model price). Slices 1–3 **LIVE** (verified real token data). Deferred:
content-capture (regulated tiers metadata-only permanently), Langfuse, A2A trace-context. **Gotcha:**
zero-recording instruments — no series until the agent's first action.

## Topology

Hub (`platform`) = collectors + backends + Grafana. Spoke (`preprod`) = collectors only, remote-write over
TGW to the hub's write-only ingest edge. **preprod spoke LIVE for all four signals.** Federated read lane
(`… (all clusters)`) for cross-cluster admin views.

## Status ledger (verified live)

- **LIVE + exercised:** data plane (all backends), P10 **preprod spoke** (all signals), real instrumented
  preprod apps, P4 alerting + owner-routing, P5 cloud-resource, P6 APM/correlation, P8 profiling, P9 SLOs, P11
  cost, P12 policy-reporter, network-flow metrics + alerts (Cilium/Hubble: `cilium_drop_count_total`,
  `hubble_flows_processed_total`) + the standalone Hubble UI, **agent-obs (ADR-076)**, per-team overview
  dashboards (#1157), per-team **write** split (real alpha/bravo tenants).
- **Built-but-inert:** per-team **read** isolation (tenant-proxy — deployed, fail-closed, but nothing consumes
  it); a leftover `p13-spike-echo` Grafana datasource (cleanup debt).
- **Designed/not built:** P14 self-service golden path (auto per-team dashboards/alerts/SLOs + Backstage);
  mTLS on the cross-cluster ingest path; Hubble flow-**log** export (#161) + dedicated Cilium/Hubble
  dashboards; prod spoke.

## Gotchas

- **`X-Scope-OrgID` is a trust header** — isolation is the network (default-deny + ClusterIP-only stores).
- **Cilium `ingress` identity (8):** obs ingress needs `CiliumNetworkPolicy fromEntities: ["ingress"]`.
- **Zero-recording instruments:** agent metrics emit nothing until the first action (cold agent = `target_info`
  only).
- **Three narrow Alloys** (logs DS / profiles privileged DS / events singleton), not one mega-agent — needed
  for per-node vs singleton topology + privilege isolation.
- **max-not-sum** on true-cost panels (#668) — the exporter re-emits the same monthly gauge; `sum` double-counts.

## Go deeper

Deep dives: [stack & storage](deep-dive-the-stack-and-storage.md) ·
[collection & instrumentation](deep-dive-collection-and-instrumentation.md) ·
[correlation & the team experience](deep-dive-correlation-and-the-team-experience.md) ·
[SLOs, alerting & cost](deep-dive-slos-alerting-and-cost.md) ·
[agent observability](deep-dive-agent-observability.md). Author obs: the `observability-authoring` skill.
Substrate: [Grafana LGTM](https://grafana.com/oss/) · [OpenTelemetry](https://opentelemetry.io/docs/) ·
[Prometheus](https://prometheus.io/docs/) · [eBPF](https://ebpf.io/) ·
[Google SRE — SLOs & burn-rate](https://sre.google/workbook/alerting-on-slos/).
