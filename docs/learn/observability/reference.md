# Learn: Observability — reference

A lookup page; the [orientation](orientation.md) builds the model. Verified against code + live (as of
this writing).

## Pinned versions (`infra/live/aws/_versions.hcl`, `helm_versions.*`)

| Component | Chart | | Component | Chart |
| --- | --- | --- | --- | --- |
| kube-prometheus-stack (Prometheus/Grafana/Alertmanager) | 87.5.0 | | Beyla (eBPF RED+traces) | 1.16.8 |
| Mimir (metrics) | 6.0.6 | | OTel Collector | 0.158.2 |
| Loki (logs) | 7.0.0 | | Sloth (SLOs) | 0.16.0 |
| Tempo (traces) | 2.25.5 | | OpenCost | 2.5.23 |
| Pyroscope (profiles) | 2.1.0 | | cortex-tenant | 0.8.1 |
| Alloy (collector) | 1.10.0 | | blackbox / policy-reporter / cloudwatch-exporter | 11.13.0 / 3.7.4 / 0.46.0 |

Components live in namespace `observability` (backends on the hub; OTel Operator in
`opentelemetry-operator-system`).

## The stack

- **LGTM+P**: Loki · Grafana · Tempo · Mimir · **P**yroscope. Each is a specialist store for one signal
  shape; all share the storage pattern: small hot buffer on a gp3 PVC + durable blocks on **S3** (one bucket
  per signal, SSE-S3/AES256 explicit — the org SCP denies PutObject without the header; S3 via **Pod
  Identity**).
- **Metrics are additive:** Prometheus is the scraper (~15d local); it remote-writes every sample to Mimir
  (durable, S3). Grafana's default datasource is Mimir, so rebuilding Prometheus loses nothing.
- **Mimir over Thanos:** native `X-Scope-OrgID` multi-tenancy, which the hub-and-spoke layout needs. Classic
  microservices arch (distributor→ingester, RF1 on the reference cluster; `high_availability` toggles RF3).
- **Grafana:** the single pane; SSO via Keycloak OIDC (`platform-admins`→Admin, else Viewer);
  Tailscale-only (internal NLB); hardened (anon off, no signup). Datasources provisioned as code, named
  `<Store> (<tenant>)` (per-tenant, static `X-Scope-OrgID`), plus the federated `<Store> (all clusters)` admin lane.
- **Why self-hosted** (vs Datadog/Grafana Cloud/AMP-AMG): SaaS and managed pricing is per-host/series or
  per-sample, so it grows with cardinality — what a multi-tenant platform generates. Self-hosted is compute you
  already run plus cheap S3; data stays in-account, dashboards-as-code, portable. Accepted trade: we operate it.

## Tenancy — `X-Scope-OrgID`

- The header names a **tenant** and the store trusts it — that's not authentication. Real isolation
  is the network: the `observability` namespace is default-deny, and stores are ClusterIP-only, never on the Gateway.
- **Cluster tenants** (LIVE, carrying data): `platform`, `preprod`. Spokes remote-write over a write-only
  Gateway HTTPRoute that force-stamps `X-Scope-OrgID`, so a spoke can't spoof another tenant.
- **Per-team tenants:** per-team **write** isolation is real — a write-path proxy (`cortex-tenant`)
  relabels series to `<team>` for env namespaces → real `alpha`/`bravo` Mimir/Loki tenants (verified S3
  blocks). Per-team **read** scoping is soft: per-tenant datasources (`Mimir (<team>)`, static
  `X-Scope-OrgID`) + **Grafana dashboard-folder permissions** + namespace-filtered per-team dashboards — an
  organizational, RBAC-level boundary, not a fail-closed data gate. The real boundary is the network
  (default-deny + ClusterIP-only stores). Cross-team sharing is soft too (share the dashboard/folder).
  Traces/profiles read scoping is deferred. (See status below.)

## Collection & the instrumentation ladder

**Platform-injected** — apps carry no telemetry config; the platform stands up collectors + instruments.

| Signal | Collector (deploy) | → Backend |
| --- | --- | --- |
| Logs | Alloy DaemonSet (node-local `/var/log/pods`) | Loki |
| K8s events | Alloy **singleton** (dedup) | Loki |
| Profiles | Alloy eBPF DaemonSet (privileged, CPU sampler) | Pyroscope |
| **RED metrics + traces** | **Beyla** eBPF DaemonSet (kernel uprobes) | Mimir (scrape) + Tempo (OTLP) |
| Cluster/infra metrics | Prometheus (hub full / spoke **agent-mode**) + KSM + node-exporter | Mimir (remote-write) |
| App traces + metrics + profiles + logs (opt-in SDK) | OTel Collector (gateway) ← app SDK | Tempo / Mimir / Pyroscope / Loki |
| AWS metrics | cloudwatch-exporter (YACE, tag-discovery) | Mimir |
| Synthetic | blackbox (`Probe` CR) · k6 (CronJob) | Mimir |
| Network flows | Cilium + Hubble (`ServiceMonitor`; chart's own off) | Mimir (+ standalone Hubble UI) |

**Ladder:** L0 **Beyla eBPF** (zero-code RED/traces/service-graph, every workload — **LIVE**) → L1 **OTel SDK**
(app wires the SDK, annotation `instrumentation.opentelemetry.io/inject-sdk` → operator injects the OTLP
endpoint; **LIVE**, 6 `Instrumentation` CRs across preprod, `alpha-shop`+`alpha-checkout` opted in) → L2
**agent-obs** (below). A workload runs L0 *or* L1, never both (SDK-annotated pods are excluded from Beyla).
Beyla replaces Tempo's metrics-generator as the RED source for un-instrumented workloads.

## Correlation (all live for L0; log↔trace needs L1)

Metric **exemplar** → **trace** (Tempo) → **logs** (Loki, `tracesToLogsV2`) → **profile** (Pyroscope, via
aligned `service.name`) — one click each, for any workload. The reverse jump, **logs → trace** (Loki
`derivedField`, `matcherType: label` against structured metadata), only resolves for L1 SDK'd
services; Beyla doesn't stamp `trace_id` into app log lines. Plus service-graph + deploy annotations. Wired
in datasource config (`exemplarTraceIdDestinations`, `tracesToLogsV2`, `tracesToProfiles`).

## Act: SLOs · alerting · cost

- **SLOs:** **Sloth** (`PrometheusServiceLevel` → SLI recording rules + **multi-window burn-rate** alerts).
  Live: an API-server 99.9% SLO. **Per-app SLOs auto-derived for every environment, any stage** from
  `gitops/environments/**/*.yaml` (99.9% HTTP success + 99% sub-500ms latency off
  `http_server_request_duration_seconds_count` — Beyla-emitted or OTLP-emitted and converged to the same
  name/labels at Mimir ingest), evaluated in the Mimir ruler — feeds the canary error-budget freeze gate.
- **Alerting:** ~60 curated alert rules across 20 groups (`observability/alerts/curated.yaml`); Alertmanager routes by
  `severity` (critical → PagerDuty + Slack + SNS; warning → Slack; inhibit critical→warning); a **dead-man's
  switch** (Healthchecks.io) pages if the pipeline goes silent. *PagerDuty status:* the critical→PagerDuty wire
  (Events-API-v2 receiver, keyed by the `pagerduty` unit's routing key) is provisioned in IaC and unchanged;
  the *delivery* leg depends on a live PagerDuty account, which is **currently offline**, so `critical`
  reaches Slack + SNS + the dead-man's switch today, not a human page. (The IaC is the durable fact; whether a
  page actually lands is an account/subscription state — confirm against the live `pagerduty` unit + Alertmanager
  before relying on it, don't trust this line's snapshot.) **Owner-routing:**
  the triage agent resolves the culprit's **team** from the git registries, pages that team's on-call,
  @-mentions the commit author in Slack.
- **Cost:** **OpenCost** (in-cluster allocation per team/ns,
  near-real-time "speedometer") + **true-cost-exporter** (AWS CUR→Athena, real unblended bill, "odometer" —
  panels aggregate `max` not `sum` to avoid double-counting the monthly gauge). Budget enforcer (Kyverno
  gate on over-budget provisioning; audit-first fail-open).

## Agent observability — LIVE

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
  `hubble_flows_processed_total`) + the standalone Hubble UI, **agent-obs**, per-team overview
  dashboards, per-team **write** split (real alpha/bravo tenants) + **soft** per-team read scoping
  (Grafana dashboard-folder permissions + per-team dashboards).
- **Cleanup debt:** a leftover `p13-spike-echo` Grafana datasource.
- **Not built:** per-team **traces (Tempo) + profiles (Pyroscope)** isolation (deferred — metrics +
  logs are the two live signals); P14 self-service golden path (auto per-team dashboards/alerts/SLOs +
  Backstage); mTLS on the cross-cluster ingest path; Hubble flow-**log** export + dedicated Cilium/Hubble
  dashboards; prod spoke.

## Gotchas

- **`X-Scope-OrgID` is a trust header** — isolation is the network (default-deny + ClusterIP-only stores).
- **Cilium `ingress` identity (8):** obs ingress needs `CiliumNetworkPolicy fromEntities: ["ingress"]`.
- **Zero-recording instruments:** agent metrics emit nothing until the first action (cold agent = `target_info`
  only).
- **Three narrow Alloys** (logs DS / profiles privileged DS / events singleton), not one mega-agent — needed
  for per-node vs singleton topology + privilege isolation.
- **max-not-sum** on true-cost panels — the exporter re-emits the same monthly gauge; `sum` double-counts.

## Go deeper

Deep dives: [stack & storage](deep-dive-the-stack-and-storage.md) ·
[collection & instrumentation](deep-dive-collection-and-instrumentation.md) ·
[correlation & the team experience](deep-dive-correlation-and-the-team-experience.md) ·
[SLOs, alerting & cost](deep-dive-slos-alerting-and-cost.md) ·
[agent observability](deep-dive-agent-observability.md). Author obs: the `observability-authoring` skill.
Substrate: [Grafana LGTM](https://grafana.com/oss/) · [OpenTelemetry](https://opentelemetry.io/docs/) ·
[Prometheus](https://prometheus.io/docs/) · [eBPF](https://ebpf.io/) ·
[Google SRE — SLOs & burn-rate](https://sre.google/workbook/alerting-on-slos/).
