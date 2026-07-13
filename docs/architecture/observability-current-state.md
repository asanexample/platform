# Observability — Current State (As-Built)

What is **actually deployed today**, and the architecture behind it. This is the operator's source of truth;
the full 14-phase roadmap (and the design rationale for phases not yet shipped) lives in
[`../plans/102-observability-stack.md`](../plans/102-observability-stack.md).

- **Use it** (access Grafana, dashboards, queries): [`../runbooks/observability-access.md`](../runbooks/observability-access.md)
- **Fix it** (troubleshooting + gotchas): [`../runbooks/observability-troubleshooting.md`](../runbooks/observability-troubleshooting.md)
- **Modules**: [`observability`](../../infra/modules/observability/README.md) · [`observability-mimir`](../../infra/modules/observability-mimir/README.md) · [`observability-loki`](../../infra/modules/observability-loki/README.md) · [`observability-tempo`](../../infra/modules/observability-tempo/README.md) · [`observability-alloy`](../../infra/modules/observability-alloy/README.md) · [`observability-otel-collector`](../../infra/modules/observability-otel-collector/README.md) · [`observability-events`](../../infra/modules/observability-events/README.md)

---

## What's live today

On the **platform** cluster, in the **`observability`** namespace:

| Component | What | Version | Notes |
|-----------|------|---------|-------|
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics + prometheus-operator | chart `87.5.0` | P1 hub — always on |
| **Grafana Loki** | Logs store (single-binary), S3-backed, **Pod Identity** | chart `loki 7.0.0` | P3a — `enable_loki` |
| **Grafana Alloy** | Log-collector DaemonSet (node-local pod logs → Loki) | chart `alloy 1.10.0` | P3a — `enable_log_pipeline` |
| **K8s events → Loki** | Alloy singleton watching cluster Events → Loki | chart `alloy 1.10.0` | P3b — `enable_log_pipeline` |
| **Grafana Tempo** | Traces store (`tempo-distributed`, minimized), S3-backed, **Pod Identity** | chart `tempo-distributed 2.25.5` (app 2.10.7, **grafana-community**) | P3b — `enable_tempo` |
| **OpenTelemetry Collector** | Trace gateway (OTLP in → Tempo) | chart `opentelemetry-collector 0.158.2` | P3b — `enable_trace_pipeline` |
| **Curated alerts** | curated rules across 20 groups (+ bundled mixins) — broad control-plane/store/access coverage after the #1124 alerting epic | — | P4 |
| **Notifications** | `warning`→Slack · `critical`→SNS+Slack+PagerDuty\* · inhibition | — | P4; secrets via ESO. \***PD paging currently offline** (trial lapsed ~2026-07-07); criticals reach SNS+Slack+dead-man's today |
| **gp3 StorageClass** | cluster-default EBS storage (EBS CSI) | — | in the `eks-addons` unit |
| **Grafana Mimir** | Durable, multi-tenant, S3-backed metrics store | chart `mimir-distributed 6.0.6` | P2 — **ON** on the platform hub (`enable_mimir=true`); Prometheus `remote_write`s here; the hub-and-spoke store |
| **Prometheus agent (preprod spoke)** | kube-prometheus-stack agent mode (+ KSM + node-exporter) on **preprod**, `remote_write`s to the hub Mimir under tenant `preprod` | chart `kube-prometheus-stack 87.5.0` | P10 — `infra/modules/observability-prometheus-agent` |
| **policy-reporter** | Watches Kyverno's PolicyReport/ClusterPolicyReport CRs → metrics + bundled Grafana dashboards (Overview/PolicyReport/ClusterPolicyReport, `$cluster` filter). Hub renders dashboards; the preprod spoke only emits metrics for the hub's federated view | chart `policy-reporter 3.7.4` | P12 — `enable_policy_reporting`, closes #93; on both platform + preprod |
| **OpenCost** | In-cluster cost allocation (namespace/workload) from node/pod usage × AWS pricing API; own metrics scraped back into Prometheus | chart `opencost 2.5.23` | P11 — `enable_cost_metrics` |
| **true-cost-exporter** | Real AWS spend (CUR via Athena, cross-account) by team/service/account, reconciled against OpenCost's estimate — OpenCost's own `cloudCost` isn't Prometheus-scrapeable, so this is the Grafana-visible path | custom exporter, `infra/modules/observability-opencost/true-cost-exporter.tf` | P11 pt2 — `enable_cloud_cost`, closes #668; platform hub only (CUR is org-wide) |

> **cost_profile (`common.hcl`/`_base.hcl`):** `dev` (default) = single-replica + durable stores **off**. The
> platform cluster overrides `enable_mimir` / `enable_loki` / `enable_log_pipeline` / `enable_tempo` /
> `enable_trace_pipeline` **on** in its `env.hcl` (so the full LGTM bundle runs single-replica), while other
> clusters stay dev/off. `cost_profile=prod` flips the bundle to HA (RF3, multi-replica).

**Grafana SSO (#592):** Grafana authenticates against **Keycloak** (OIDC `generic_oauth`, the `grafana` client
from keycloak-config — same pattern as ArgoCD/Backstage). Group→role: `platform-admins` → **Admin**, any other
authenticated user → **Viewer** (per-team Editor scoping is P13/#590). The client secret syncs from Secrets
Manager via ESO; the backend OIDC calls reach Keycloak through the gateway Envoy (a host-alias to its ClusterIP)
to dodge the internal-NLB hairpin. The local admin login remains as break-glass.

---

## Architecture

### Hub-and-spoke (single hub today)

The design is **hub-and-spoke**: one central hub (the **platform** cluster) runs Grafana + the durable
stores; spoke clusters run lightweight collectors that `remote_write` to the hub over the Transit Gateway.
The hub monitors itself (its own Prometheus → the hub Mimir, tenant `platform`), and **preprod** is a spoke for
all three signals under tenant `preprod`: **metrics** (P10 — a kube-prometheus-stack agent → hub Mimir),
**logs** (#627 — an Alloy DaemonSet → hub Loki, `cluster=preprod`), and **traces** (#628 — an OTel collector
→ hub Tempo, `cluster=preprod`; the collector carries real workload traces once P7 instruments preprod).

**Cross-cluster ingest edge (Gateway-API-native, no proxy).** The hub Mimir is `ClusterIP`-only; spokes reach
it through a write-only **HTTPRoute** on the shared Cilium Gateway (`<spoke>-mimir.aws.refplat.org`,
self-routed by the `observability-mimir` module's `spoke_ingest` input). The HTTPRoute does two
security-critical jobs declaratively: a `RequestHeaderModifier` **force-sets `X-Scope-OrgID`** to the spoke's
tenant — overwriting any client value, so a spoke can't spoof another tenant (the ADR-044 guard) — and a path
match on `/api/v1/push` keeps it **write-only** (no query path is exposed cross-cluster). A
`CiliumNetworkPolicy` (`fromEntities: ["ingress"]`) admits the Gateway Envoy to the Mimir gateway past the
`observability` default-deny. **Auth = network isolation** (the internal NLB reachable only over the VPC/TGW);
mTLS is the planned P10.x hardening. The spoke sends **no** tenant header (the edge sets it) and **no**
credential. Onboarding the next spoke: [`observability-spoke-onboarding.md`](../runbooks/observability-spoke-onboarding.md).

```text
              ┌─────────────────────────  observability namespace (platform cluster)  ──────────────────────┐
  scrapes     │  Prometheus ──remote_write(X-Scope-OrgID: platform)──▶  Mimir gateway ─▶ distributor        │
  cluster ───▶│   │  (15d local, gp3 PVC)                                 │              ▶ ingester ─┐       │
  targets     │   │                                                       │              ▶ querier   │ S3   │
              │   ▼                                                  query │              ▶ q-frontend│blocks│
              │  Alertmanager ──sns_configs(sigv4/Pod Identity)──▶ SNS ─▶ email │           ▶ store-gw ◀─┘bucket│
              │   │  (gp3 PVC)                                             │              ▶ compactor ─▶ S3   │
              │   ▼                                                        │                                  │
              │  Grafana ◀── Mimir datasource (default, X-Scope-OrgID: platform) ─────────┘                  │
              │   ▲   ◀── Prometheus datasource (recent/local, non-default)                                  │
              └───┼──────────────────────────────────────────────────────────────────────────────────────────┘
                  │ HTTPRoute (Cilium Gateway, internal NLB, cert-manager TLS)
            grafana.aws.refplat.org   ◀── Tailscale-only (no public exposure)
```

### Metrics path: Prometheus + Mimir (additive)

Prometheus stays the **scraper** with a short local retention (15d, on a gp3 PVC); it **`remote_write`s**
every sample to **Mimir**, which is the durable, long-range store on **S3**. Grafana's **default datasource
is Mimir** (full history); the Prometheus datasource remains selectable for recent/local queries. This is
additive — no migration, and Prometheus can be lost/rebuilt without losing history (it's in Mimir/S3).

Mimir runs in **classic architecture** (distributor → ingester gRPC, RF1), *not* the chart's default Kafka
ingest-storage — lighter for a reference cluster. Components: gateway (nginx), distributor, ingester,
querier, query-frontend, **query-scheduler** (required — the chart wires querier→scheduler), store-gateway,
compactor. Ingester/store-gateway/compactor are StatefulSets on **gp3** PVCs; durable blocks live in the
**AES256** S3 bucket reached via **EKS Pod Identity** (ADR-047, no static keys).

> Mimir is **ON** on the platform hub today (`enable_mimir=true` in the platform `env.hcl`); the above is the
> live metrics path. Other clusters default to the `dev` cost_profile with Mimir off, where Prometheus serves
> metrics directly (no remote-write).

### Logs path: Loki + Alloy (P3a)

**Grafana Alloy** runs as a DaemonSet — each agent tails *its own node's* `/var/log/pods` (a
`spec.nodeName`-filtered `discovery.kubernetes` + `loki.source.file`, so no duplicate ingestion) and writes
to **Loki** under tenant `platform`. A second Alloy **singleton Deployment** watches the Kubernetes **Events**
API (`loki.source.kubernetes_events`) and ships events to Loki too — so events sit next to logs. Loki runs
single-binary; durable chunks live on **S3 via Pod Identity** (ADR-047 — no IRSA), and it's the Grafana
**Loki** datasource. Per-team tenant derivation is P10.

### Traces path: Tempo + OpenTelemetry Collector (P3b)

Apps send **OTLP** to a deployment-mode **OpenTelemetry Collector** (`otelcol-k8s`;
`otlp → memory_limiter → batch → otlp/tempo`), which forwards to **Tempo**'s distributor. Tempo uses the
`tempo-distributed` chart **minimized for dev** (each component 1 replica, RF1, caches/gateway off;
`prod` scales it via `high_availability`); durable blocks on **S3 via Pod Identity**. The Grafana
**Tempo** datasource links **traces↔logs** (`tracesToLogsV2` → Loki; Loki's `trace_id` derived field → Tempo,
`matcherType: label` — see below).

### APM correlation: metrics-generator + exemplars (P6)

The Tempo **metrics-generator** is **on** — it derives **RED span-metrics** (`traces_spanmetrics_*`) and a
**service graph** (`traces_service_graph_*`) from traces and `remote_write`s them to **Mimir per-tenant**
(X-Scope-OrgID preserved). The Tempo datasource's `serviceMap` points at the matching Mimir datasource so
Grafana renders the **node graph** (e.g. `user → app-alpha-shop`). **Exemplars** close the metric → trace loop:
the generator's remote_write sets `send_exemplars` so each span-metric point carries the span's `traceID`, Mimir
stores them (`max_global_exemplars_per_user`), and the Mimir datasource's `exemplarTraceIdDestinations` link a
latency spike → the **trace** → (tracesToLogs) → **logs**. **Log → trace is closed the other direction too**
(ADR-100): the per-team Alloy pipeline (`observability-alloy`, the `retenant` process) promotes each SDK'd app's
`trace_id`/`span_id` out of the JSON log body into **Loki structured metadata**, and the Loki datasource's
derived field links on that field directly (`matcherType: label`) rather than regex-scraping the line — a log
line jumps straight to its trace. (Only SDK-instrumented services carry these fields; Beyla-only workloads still
rely on trace↔metrics/service-graph correlation, not log↔trace.) The
generator also runs the **`local-blocks`** processor, which powers
Grafana's **Traces Drilldown** (TraceQL *metrics* queries — `rate()`/`quantile_over_time()` over spans).

### SLOs & error budgets (P9)

**Sloth** turns abstract SLO definitions (`{ objective, error/total query }`, the `observability-slo` module's
`slos` input) into **SLI recording rules** + **multi-window burn-rate alert rules**. Its controller watches
`PrometheusServiceLevel` CRs and emits `PrometheusRule`s, which the hub Prometheus discovers + evaluates;
the SLO metrics (`slo:sli_error:*`, `slo:current_burn_rate:ratio`, …) remote-write to Mimir, and burn-rate
**alerts route via the P4 Alertmanager** by severity (`pageAlert`=critical, `ticketAlert`=warning). First SLO:
**API server request availability** (99.9%). The grafana.com **"High level Sloth SLOs"** dashboard (14643) is
provisioned as code. `slo_engine` is the seam for a future Pyrra/Grafana-SLO swap.

### Per-app SLOs (registry-derived, ADR-056 Phase 3 — distinct from Sloth above)

A **second, separate** SLO mechanism covers application environments, live since ADR-056 Phase 3
(#900/#882). Unlike the Sloth SLOs above (manually authored per platform service), an app SLO is
**derived automatically** for every `prod` `XEnvironment` claim — the `mimir` unit's Terragrunt scans
`gitops/environments/**/prod.yaml` (`fileset`+`yamldecode`) and generates one fixed **99.9%
HTTP-success-rate** SLO per environment from Beyla's RED metrics
(`http_server_request_duration_seconds_count{k8s_namespace_name="<env>"}`), rendered as multi-window
burn-rate rules into an **`app-slos`** **Mimir ruler namespace** (synced by `mimirtool rules sync`, not
Sloth's `PrometheusServiceLevel`→`PrometheusRule` path). There's no per-Product objective override
today — the 99.9% target is a fixed template.

**Consumer: the ADR-056 canary error-budget freeze gate.** Before any Rollout traffic shifts, a
one-shot `AnalysisTemplate` queries `slo:current_burn_rate:ratio{sloth_id="<env>-availability"}` — if
the environment is already burning ≥2× its 30-day error budget (an active incident), the deploy is
**frozen** before it starts, rather than layering a risky deploy on top of an ongoing incident. This is
distinct from the ADR-056 canary-gate `AnalysisStep` (which watches the *new* version's live success
rate during rollout) — the freeze gate asks "is it safe to deploy at all," the canary gate asks "is
this deploy working."

### Continuous profiling (P8)

**Pyroscope** (`observability-pyroscope`) is the profiles store — the **P** in LGTM+P. Monolithic
single-binary StatefulSet (metastore + segment-writer embedded), S3-backed (SSE-S3 + EKS Pod Identity, no
static keys), multi-tenant by `X-Scope-OrgID` (each cluster a tenant), with a `Pyroscope (<tenant>)` Grafana
datasource. Mirrors the Loki/Tempo/Mimir store pattern. **Config note:** Pyroscope's S3 config is
Grafana/dskit-lineage (`bucket_name` + `sse.type` + an explicit `endpoint`), *not* Thanos-style.

**Collection** is zero-code: a privileged **Alloy** eBPF DaemonSet (`observability-pyroscope-ebpf` —
`pyroscope.ebpf` → `pyroscope.write`, like the Beyla agent) CPU-profiles every process on each node, labelling
each by `service_name` = the `app.kubernetes.io/name` label (falling back to namespace) so it **matches
Beyla's trace `service.name`**. It runs on **both clusters**: the platform profiler writes locally; the
**preprod profiler** writes to the hub via the same write-only, tenant-overwriting Gateway edge as the other
spokes (`preprod-profiles.aws.refplat.org`), landing under the `preprod` tenant. The Tempo datasource's
`tracesToProfilesV2` links a span → its CPU flame graph in the matching Pyroscope tenant (`tempo`→`pyroscope`,
`tempo-preprod`→`pyroscope-preprod`). The trace→flame-graph jump resolves for any CPU-using traced service
(the trivial echo demo apps don't burn enough CPU to flame-graph under load).

**Synthetics (P9b)** — the **blackbox-exporter** (`observability-blackbox`) probes the platform HTTPRoute
endpoints (grafana/argocd/backstage/keycloak) over HTTP/TLS via a `Probe` CR → `probe_success`,
`probe_ssl_earliest_cert_expiry`, latency in Mimir. To dodge the internal-NLB hairpin (a pod can't reliably
reach an internal NLB that targets its own cluster), the exporter `hostAlias`es the probe hostnames to the
Cilium Gateway Envoy **ClusterIP** — testing Gateway routing + TLS directly (keeping the real SNI/Host). k6
scripted checks are the remaining synthetics follow-up.

### Multi-cluster view — federated datasource (#626)

Each cluster is a separate Mimir tenant (`platform`, `preprod`), so by default one datasource = one cluster
(strong read-isolation). For a **platform-admin overview across clusters**, Mimir **tenant federation** is
enabled (`tenant_federation.enabled`) and a **`Mimir (all clusters)`** Grafana datasource queries every tenant
at once (`X-Scope-OrgID: platform|preprod`). The same applies to logs and traces: **`Loki (all clusters)`** and
**`Tempo (all clusters)`** datasources federate across tenants (Loki/Tempo do multi-tenant queries via the
pipe-separated header). Write-isolation is unaffected — each store's Gateway edge still force-stamps a single
tenant per spoke. (Tempo runs `multitenancyEnabled`; the hub OTel collector stamps the hub's own Beyla traces
as tenant `platform`.) The **Platform Health** dashboard defaults to this datasource and has
a `cluster` multi-select, so panels break out per cluster. Per-team tenancy (**P13**, #590) is **parked**
(ADR-104) — see the subsection below. Cross-cluster **logs/traces** federation follows their spokes
(#627/#628). Umbrella: #629.

### Per-team tenant isolation (P13, #590) — PARKED (ADR-104)

Per-team tenancy was built as write-only (metrics dual-write via `cortex-tenant`, logs re-tenanted by
Alloy); a hard read-proxy (`observability-tenant-proxy` + `loki-tenant-proxy`) was also built but
**retired (#1269)** — OSS Grafana's `oauthPassThru` can't reliably forward the SSO token to a downstream
proxy, so the proxy fail-closed on `no_token` and blanked every dashboard for admins. That left per-team
*writes* real but per-team *reads* soft (folder permissions + namespace-filtered dashboards, #1157) —
and traces/profiles never got a per-team path at all, so tenancy was inconsistent across signals
(metrics/traces on the **cluster** tenant, logs on the **team** tenant).

**ADR-104** standardizes on **cluster tenancy for all three signals** instead of finishing the per-team
split: there's no current hard-isolation requirement, and OSS Grafana can't enforce per-team reads
regardless (Enterprise-only datasource RBAC), so the split delivered zero real isolation. `cortex-tenant`
is decommissioned; the already-inert `tenant-proxy`/`loki-tenant-proxy` are removed too; `alpha`/`bravo`
drop from the `loki`/`mimir` federated datasources, leaving `platform`/`preprod` as the only tenants. Soft
per-team scoping (dashboard folder permissions + namespace-filtered dashboards, #1157) is unaffected and
remains the actual team-facing boundary. Per-team tenancy can be rebuilt later — for all signals, paired
with a real Grafana read-enforcement decision — if a hard-isolation need appears.

> **Known wrinkle (data layer only):** the Loki/Mimir charts stamp their own `cluster` label on self-metrics
> (`cluster=loki`/`cluster=mimir`), polluting the raw `cluster` dimension. The dashboard's `cluster` dropdown
> sidesteps this by deriving values from `kube_node_info` (KSM — real clusters only), so the UI is clean;
> relabeling the self-metrics so `externalLabels.cluster` is authoritative is tracked in #630.

### Dashboard template-variable convention (#151)

Every dashboard carries a `$cluster` variable (`cluster=~"$cluster"` on every panel) — the label is on
every series regardless of what the dashboard is about (Prometheus `externalLabels`, ADR-043/044).
Tenant/namespace-scoped dashboards (workload health, cost, APM) additionally carry `$namespace`/`$team`;
cluster/node-level dashboards (Platform Health, Cilium) don't, since there's nothing tenant-scoped to
filter. The vendored **ArgoCD** dashboard shipped its own `cluster` variable meaning something else
entirely (the ArgoCD-**target** server apps deploy *to*, `label_values(argocd_cluster_info, server)`) —
renamed to `dest_cluster` so `$cluster` means the same thing on every dashboard. Authoring detail: the
`observability-authoring` skill's "Add a dashboard" section.

### Multi-tenancy & the security boundary (read this)

Mimir runs with `multitenancy_enabled: true`. The tenant is the **`X-Scope-OrgID`** header; the hub's own
metrics use tenant **`platform`**. When spokes onboard (P10), each writes under its own tenant.

> **`X-Scope-OrgID` is a trust header, not authentication.** Mimir does not authenticate it — anything that
> can reach the Mimir endpoint and set the header can read/write any tenant (the nginx gateway even fills in
> a default tenant when the header is absent). **The actual isolation boundary is the NetworkPolicy:** the
> `observability` namespace has a **default-deny ingress** + an allow only for intra-namespace traffic, so
> `team-*` (and every other) namespace **cannot reach Mimir at all**. Mimir is **never** exposed through the
> Cilium Gateway (ClusterIP only — unlike Grafana). Cross-cluster ingest from spokes (P10) must be
> authenticated and have the header overwritten at the hub edge.

### Network & exposure

- **Grafana** is the only externally-reachable component: an HTTPRoute on the Cilium Gateway (internal NLB,
  `internal` scheme) → **Tailscale-only**, TLS via cert-manager (Let's Encrypt DNS-01). Hardened: anonymous
  off, no sign-up/org-create, viewers can't edit, secure cookies, unsigned plugins disabled.
  - **Gotcha:** the Cilium gateway's Envoy connects with the reserved Cilium `ingress` identity (8), which a
    standard k8s NetworkPolicy `from:` can't match — Grafana ingress is allowed via a **CiliumNetworkPolicy**
    `fromEntities: ["ingress"]`. (CLAUDE.md "Cilium Gateway API".)
- **Namespace PSA** = `privileged` (node-exporter needs hostNetwork); the namespace is created by Terraform
  (not the chart) so the label is set, and intentionally carries **no tenant label** (so Kyverno tenant
  policies don't apply; `observability` is also in the policy `exclude_namespaces`).

### Alerting (P4)

Bundled Prometheus mixin rules are on; **EKS-inaccurate groups are disabled** (`kubeScheduler`,
`kubeControllerManager`, `kubeEtcd`, `kubeProxy`) — the managed control plane is unscrapeable and Cilium
replaces kube-proxy. On top of the mixins, **31 curated `PrometheusRule`s** cover 8 components —
cert-manager, kyverno, policy-reporter, ArgoCD, Loki, Tempo, External Secrets, Cilium (+ Hubble) — each grounded in
live-verified metrics with a `runbook_url` → [`observability-alerts.md`](../runbooks/observability-alerts.md).
Component metrics are scraped via the chart's `additionalServiceMonitors`/`additionalPodMonitors` (the
Cilium/ESO chart ServiceMonitors are off or capability-gated, so we define them on the observability side —
see Gotchas). Rules live in `infra/modules/observability/alerts/curated.yaml`.

**Routing** — severity tree with inhibition (a `critical` suppresses a matching `warning`):

| severity | destinations |
|----------|-------------|
| `critical` | **SNS** (email) + **Slack** (`#platform-alerts`) + **PagerDuty** (page; Events API v2) |
| `warning` | **Slack** |
| `info` / `Watchdog` / else | dashboard-only (`null`) |

SNS publishes via **sigv4 + EKS Pod Identity** (ADR-047; SSE-KMS topic). The **Slack webhook** and **PagerDuty routing key** are
synced from Secrets Manager by **External Secrets** and read by Alertmanager via `api_url_file` /
`routing_key_file` — the secrets never enter Terraform state or helm values (see the
[notification-channels runbook](../runbooks/observability-alerts.md#notification-channels--secret-rotation)).
**Deploy/change annotations** (a Prometheus query on `kube_deployment_metadata_generation` changes) overlay
the platform dashboards so a metric blip can be tied to a rollout.

### Storage model

| Data | Where | Durability |
|------|-------|-----------|
| Prometheus TSDB (15d local) | gp3 PVC (20Gi) | survives pod restart; rebuildable from scrape |
| Alertmanager state | gp3 PVC (5Gi) | — |
| Mimir ingester WAL / store-gateway / compactor scratch | gp3 PVCs (10/10/20Gi) | local working set (Mimir on, platform hub) |
| **Mimir blocks (durable history)** | **S3** (AES256, versioned, lifecycle-pruned) | the long-term metrics store |
| **Loki chunks (logs)** | **S3** (AES256, SSE-S3 request header, Pod Identity) | durable log store |
| **Tempo blocks (traces)** | **S3** (AES256, SSE-S3 request header, Pod Identity) | durable trace store; `block_retention` 72h |
| Loki / Tempo-ingester WAL | gp3 PVCs (~5Gi) | local working set |

gp3 is the cluster-**default** StorageClass (encrypted, expandable, WaitForFirstConsumer), created in the
`eks-addons` unit.

### Decisions & gotchas (durable)

- **Add-ons use EKS Pod Identity, not IRSA** (ADR-047). Loki/Tempo/Pyroscope, **Mimir S3**, the
  **Alertmanager→SNS** publish, cert-manager, external-dns, external-secrets, and crossplane all trust
  `pods.eks.amazonaws.com` (no `eks.amazonaws.com/role-arn` annotation) — the **#594** batch migration is done
  for these. The lone exception is the **EBS CSI managed add-on**, which legitimately stays on IRSA.
- **The org `enforce-encryption` SCP denies `s3:PutObject` without the `x-amz-server-side-encryption`
  header** — bucket default encryption alone doesn't add it. **Every S3 client must send SSE explicitly**
  (Loki `storage.s3.sse=SSE-S3`, Tempo `storage.trace.s3.sse=SSE-S3`). Loki was the first store to actually
  write, so it surfaced this; Mimir needs the same when enabled.
- **The External Secrets role is scoped to `secret:platform/*`** (the platform `external-secrets` unit sets
  `secret_path_prefix=platform`). **Every ES-synced Secrets Manager secret must be named `platform/…`** or
  ESO gets `AccessDenied` (the Slack webhook + PD routing-key secrets live under that prefix).
- **Chart ServiceMonitors are unreliable, so scraping is defined on the observability side.** Cilium's chart
  ServiceMonitors are intentionally off (Cilium installs before the Prometheus-operator CRDs in the DAG);
  the ESO chart's ServiceMonitor is capability-gated and didn't render via the helm provider. Both are
  scraped via `additionalServiceMonitors` / `additionalPodMonitors` in the observability module instead.
- **Tempo's Helm charts moved to `grafana-community/helm-charts`** (Jan 2026; the `grafana/helm-charts`
  copies are `deprecated:true`), so `tempo-distributed` is pulled from the community repo. Loki/Mimir/Alloy
  charts are unaffected. (`k8s-monitoring` is a *collector* chart, not a backend deploy — not used.)
- **Manual `terragrunt apply` on platform units needs `AWS_PROFILE=management`** (per `.platctl.yaml`; a bare
  shell is the mgmt IAM user and 403s assuming `PlatformDeployer`).

---

## Where it's defined (code map)

| Concern | Path |
|---------|------|
| P1 hub module (+ alerting routing, dashboards, ES-synced Slack/PD secrets) | `infra/modules/observability/` |
| Curated alert rules | `infra/modules/observability/alerts/curated.yaml` |
| Logs — store / collector | `infra/modules/observability-loki/` · `infra/modules/observability-alloy/` |
| Events → Loki | `infra/modules/observability-events/` |
| Traces — store / collector | `infra/modules/observability-tempo/` · `infra/modules/observability-otel-collector/` |
| Metrics durable store (+ cross-cluster `spoke_ingest` edge + `app_slos` ruler namespace) | `infra/modules/observability-mimir/` |
| Per-app SLO derivation (registry → `app_slos` input) | `infra/live/aws/platform/us-east-1/platform/mimir/terragrunt.hcl` |
| Canary error-budget freeze gate (`AnalysisTemplate`) | `scaffolder/templates/new-product/skeleton/k8s/overlays/prod/progressive.yaml` |
| Metrics spoke collector (preprod) | `infra/modules/observability-prometheus-agent/` · runbook `docs/runbooks/observability-spoke-onboarding.md` |
| SNS topic | `infra/modules/aws/sns-notifications/` |
| gp3 StorageClass | `infra/modules/aws/eks-addons/` (`create_default_storageclass`) |
| Live units (platform) | `infra/live/aws/platform/us-east-1/platform/{observability,loki,alloy,events,tempo,otel-collector,mimir,sns-notifications,eks-addons,gateway-config}/` |
| Live units (preprod spoke) | `infra/live/aws/preprod/us-east-1/platform/observability-spoke/` |
| Dashboards (as code) | `infra/modules/observability/dashboards/*.json` |
| cost_profile toggle | `infra/live/aws/common.hcl` + `_base.hcl`; per-cluster overrides in `…/platform/env.hcl` |
| Versions | `infra/live/aws/_versions.hcl` (`helm_versions.{kube_prometheus_stack,mimir,loki,alloy,tempo,otel_collector}`) |

---

## Status notes

- **P3 (logs + traces) and P4 (alerting + notifications) are applied and live** on the platform cluster
  (PRs #596–#612): logs queryable in Grafana (Loki + Alloy + K8s events), traces flowing (Tempo + OTel
  collector, with trace↔logs correlation), and 31 curated alerts routing to SNS / Slack / PagerDuty.
- **Metrics run through Mimir on the platform hub** — `enable_mimir=true`, so Prometheus `remote_write`s to
  Mimir and **Mimir is Grafana's default metrics datasource** (full history on S3); the Prometheus datasource
  stays selectable for recent/local queries. The P2 Mimir path merged as PR #147. Known wrinkle when first
  enabling on a cluster: a prometheus-operator webhook-latency gotcha during the helm reconcile — see the
  [troubleshooting runbook](../runbooks/observability-troubleshooting.md).
- **Sizing follows `cost_profile`** — `dev` (default) is single-replica with durable stores off; `prod`
  flips the bundle to HA/RF3. The platform cluster runs `dev` sizing with the durable stores (Mimir + logs +
  traces) toggled **on**.
- **Grafana SSO** (OIDC against Keycloak, #592) is **live** — see "Grafana SSO" above. Group→role mapping
  (`platform-admins`→Admin, else Viewer) is applied; the local-admin login is retained as break-glass.
