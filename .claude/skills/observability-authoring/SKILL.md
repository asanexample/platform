---
name: observability-authoring
description: >-
  How to author and extend the LGTM+P observability stack (Mimir/Loki/Tempo/
  Pyroscope + Grafana, the observability* modules). Use when adding a Grafana
  dashboard, a Prometheus alert, or an SLO; instrumenting a workload (Beyla eBPF
  baseline vs OTel-Operator SDK inject); onboarding an observability spoke; or
  reasoning about the hub-and-spoke / multi-tenant (X-Scope-OrgID) architecture and
  the cost/HA toggles. Covers the dashboards-as-code ConfigMap pattern, the curated
  alerts file, the Sloth SLO inputs, the instrumentation layers, and the durable
  gotchas. NOT for QUERYING live data or on-call (use the `grafana` MCP or
  `firing-alerts`), NOT for diagnosing an observability outage (use the
  observability-troubleshooting runbook), NOT for generic module .tf style
  (`terraform-style`).
---

# Authoring the observability stack (LGTM+P)

**Topology:** the **platform cluster is the hub** (central Grafana + durable
multi-tenant stores); **preprod is the first spoke** (lightweight collectors
remote-writing to the hub). Each cluster is a tenant via the `X-Scope-OrgID` header.
The 14-phase roadmap + architecture is `docs/plans/102-observability-stack.md`; as-built
status is `docs/architecture/observability-current-state.md`.

Modules: `infra/modules/observability` (the hub umbrella: kube-prometheus-stack +
Grafana + Alertmanager + dashboards + alerts) and 16× `observability-*` (the stores and
collectors: mimir, loki, tempo, pyroscope, alloy, beyla, otel-collector, otel-operator,
prometheus-agent, slo, blackbox, cloudwatch-exporter, events, opencost, k6,
pyroscope-ebpf). Data paths: metrics→Mimir, logs→Loki (via Alloy), traces→Tempo (via the
OTel Collector gateway), profiles→Pyroscope (via eBPF). All stores run
`multitenancy_enabled: true`.

## Add a dashboard (dashboards-as-code)

Dashboards are **Grafana sidecar ConfigMaps** — JSON files under
`infra/modules/observability/dashboards/`, each rendered into a
`kubernetes_config_map_v1` labeled `grafana_dashboard = "1"` (the sidecar scans the
label cluster-wide).

1. **Vendored upstream**: download the grafana.com JSON **pinned to an exact revision**
   (don't import-by-ID live — pin so upgrades go through PR review). Replace hardcoded
   datasource UIDs with the provisioned name/variable (e.g. `Mimir`, `Loki`, `Tempo`, or
   `"uid": "${datasource}"`). Commit to `dashboards/`.
2. **Custom**: author JSON, query the datasource variable.
3. **Template variables (#151 convention)**: every dashboard needs a `$cluster` variable
   (`label_values(<any metric this dashboard queries>, cluster)`) filtering panels with
   `cluster=~"$cluster"` — every series carries this label (Prometheus `externalLabels`,
   ADR-043/044), so it's always available regardless of what the dashboard is about.
   Tenant/namespace-scoped dashboards (workload health, cost, APM) additionally need a
   `$namespace`/`$team` variable (`label_values(..., namespace)`, filtered to `team-*`
   where relevant) with `namespace=~"$namespace"`. Cluster/node-level dashboards (health,
   Cilium) skip the namespace variable — there's nothing tenant-scoped to filter. If a
   vendored dashboard already ships its own same-named variable for an unrelated concept
   (e.g. the ArgoCD dashboard's `cluster` = the ArgoCD-target `dest_server`, not our
   source-cluster label), rename the vendored one (e.g. `dest_cluster`) rather than
   overload `$cluster` with two meanings — see `dashboards/argocd.json`.
4. `terragrunt apply` the observability unit → the ConfigMap is created and the sidecar
   picks it up within seconds.

## Add an alert

Curated platform rules live in **`infra/modules/observability/alerts/curated.yaml`** —
one `PrometheusRule` group per component, loaded into the Prometheus CR via
`additionalPrometheusRulesMap`. (Mixin rules from the chart are tier-1 and auto-loaded;
EKS-inaccurate groups are disabled.)

```yaml
- alert: MyComponentDown
  expr: up{job="my-component"} == 0
  for: 10m
  labels: { severity: critical }     # critical→SNS+Slack+PagerDuty(*), warning→Slack, info→dashboard-only
  # (*) PagerDuty is WIRED (the critical receiver has a real PD Events-API-v2 route), but paging is currently
  # OFFLINE — the PD trial account lapsed (~2026-07-07), so criticals presently reach only SNS + Slack + the
  # external dead-man's switch. Restore the PD account to re-enable paging; the wire itself needs no change.
  annotations:
    summary: "My component is down"
    description: "{{ $labels.instance }} unreachable for 10m."
    runbook_url: "https://github.com/asanexample/platform/blob/main/docs/runbooks/observability-alerts.md#my-component"
```

**Verify the PromQL live first** (grafana MCP / Prometheus), add the matching section to
`docs/runbooks/observability-alerts.md`, then apply. Routing is severity-based in the
Alertmanager config (`main.tf`), with critical→warning inhibition.

## Add an SLO (Sloth)

`infra/modules/observability-slo/` runs Sloth: an abstract `PrometheusServiceLevel`
renders into SLI recording rules + multi-window burn-rate alerts. Define SLOs in the
unit's `slos` input:

```hcl
slos = [{
  name        = "kubernetes-apiserver"
  service     = "kubernetes-apiserver"
  slo_name    = "requests-availability"          # required
  description = "API server request availability" # required
  objective   = 99.9
  error_query = "sum(rate(apiserver_request_total{code=~\"5..\"}[{{.window}}]))"
  total_query = "sum(rate(apiserver_request_total[{{.window}}]))"
  alert_name  = "K8sApiserverAvailability"
}]   # per-SLO severities default page=critical / ticket=warning (page_severity/ticket_severity optional)
```

`{{.window}}` is a Sloth placeholder — it passes through Helm untouched and Sloth fills
it per burn-rate window. The Sloth dashboard is provisioned by the module. Burn-rate
alerts route through the same Alertmanager (page = critical, ticket = warning).

## Per-app SLOs (registry-derived, live — distinct from Sloth above)

Every `prod` environment gets an SLO **automatically** — no authoring step, no `slos` input
to edit. The `mimir` unit's Terragrunt scans every `gitops/environments/**/prod.yaml`
(`fileset` + `yamldecode`, the repo's usual registry-derivation idiom) and derives one fixed
**99.9% HTTP-success-rate** SLO per environment from Beyla's RED metrics
(`http_server_request_duration_seconds_count{k8s_namespace_name="<env>"}`). There's no
`Product`/`XEnvironment` field to set — the objective is a fixed template today (a
per-Product/tier override is a possible future knob, not built). The rendered SLOs go into
an `app-slos.yaml` Mimir **ruler** namespace (multi-window burn-rate rules, Google-SRE
thresholds), synced by the module's `mimirtool rules sync` CronJob — a different delivery
path than Sloth's `PrometheusServiceLevel` CRs above.

**Structural contrast with Sloth:**

| | Per-app SLOs (`app_slos`) | Sloth platform SLOs |
|---|---|---|
| Scope | Every prod environment (auto) | Platform services (manual) |
| Source | `gitops/environments/**/prod.yaml`, registry-derived | Terragrunt `slos` input, hand-authored |
| Objective | Fixed 99.9% (no override yet) | Per-SLO in the input |
| Delivery | Rendered into a Mimir **ruler** namespace | `PrometheusServiceLevel` CR → Sloth controller → `PrometheusRule` |
| Consumer | The ADR-056 canary **error-budget freeze gate** (pre-flight) | General platform alerting |

**Where it's used:** an `AnalysisTemplate` runs once before any Rollout traffic shifts,
querying `slo:current_burn_rate:ratio{sloth_id="<env>-availability"}` — if the service is
already burning ≥2× its 30-day budget (an active incident), the deploy is **frozen** before
it starts (ADR-056 Phase 3 / the W11 freeze gate). See
`infra/modules/observability-mimir/variables.tf` (`app_slos` input),
`infra/live/aws/platform/us-east-1/platform/mimir/terragrunt.hcl` (the derivation), and
`scaffolder/templates/new-product/skeleton/k8s/overlays/prod/progressive.yaml` (the gate).

## Instrument a workload (ADR-077, three layers)

- **Layer 0 — Beyla eBPF (automatic, zero code)**: a DaemonSet emits RED metrics
  (`http_server_request_duration_seconds_*`) + service graph + request traces for
  workloads in the scoped `discovery.instrument` namespaces. No app change, all
  languages. Verify per `docs/runbooks/observability-instrumentation-verify.md`.
- **Layer 1 — OTel SDK, the golden path (ADR-100)**: annotate the workload
  `instrumentation.opentelemetry.io/inject-<lang>: "observability/platform"` (Go apps: see
  `alpha-shop`'s `internal/telemetry` package for the reference shape) — the operator injects
  the SDK + the platform-provided OTLP endpoint (never hardcode it), giving traces + metrics +
  Pyroscope profiles + trace-stamped structured logs. **Run this OR Beyla on a service, never
  both** — Beyla's eBPF context-propagation overwrites the SDK's `traceparent`, fragmenting
  traces. **For metrics specifically: a `MeterProvider` must be created and set globally
  (`otel.SetMeterProvider`) alongside the `TracerProvider`** — `otelhttp` middleware silently
  emits no RED metrics without it (tracing alone doesn't need this, which is why it's easy to
  forget). To rule out app-side bugs before chasing the collector/Mimir: write a small local
  test against a mock OTLP HTTP endpoint (or an SDK `ManualReader`) asserting the expected
  metric/span actually gets recorded/exported — much faster than debugging in-cluster.
- **Layer 2 — Agent/GenAI obs (ADR-076)**: agents emit OTel GenAI semconv
  (`gen_ai.*`), one correlated trace per invocation → audit/eval/cost/debug; content
  capture is gated per compliance tier. Deferred to the tier-0 agent build.

## House conventions

- These are **Helm-wrapping modules**: `main.tf` (release + ServiceMonitors +
  NetworkPolicy + dashboard/alert ConfigMaps), `variables.tf`, `outputs.tf`. Scrape via
  `additionalServiceMonitors`/`additionalPodMonitors` on the observability side — chart
  ServiceMonitors are unreliable for some components (Cilium, ESO).
- **Sizing**: per-unit `high_availability` bool (single-replica dev vs multi-replica +
  PDB + RF3 prod, needs ≥3 nodes / ≥2–3 AZs); cluster-wide `cost_profile` (dev disables
  durable stores → Prometheus-only; platform overrides enable Mimir/Loki/Tempo).
- **Identity**: new add-ons use EKS Pod Identity (ADR-047); some legacy components still
  IRSA (batch migration). Grafana CloudWatch access is Pod Identity.
- **Secrets**: all named `platform/*` (ESO scoped there via Pod Identity, ADR-047) — Grafana admin/OIDC,
  Slack webhook, PagerDuty key.
- **Per-team on-call**: the global PagerDuty receiver here pages one routing key; per-team on-call
  schedules + escalation policies as code live in the `pagerduty` module (ADR-084) — see its README.
- **Exposure**: Grafana on the internal Cilium Gateway, Tailscale-only; stores are
  ClusterIP-only, never exposed. Cross-cluster ingest is a Gateway HTTPRoute that
  **force-overwrites `X-Scope-OrgID`** at the edge.

## Gotchas

- **`X-Scope-OrgID` is a trust header, not auth** — isolation rests on namespace
  default-deny + edge header-rewriting + per-tenant limits. Spoke→hub is currently
  network-isolated (Tailscale/TGW), full mTLS deferred.
- **emptyDir→PVC migration deadlocks `helm --wait`** (immutable volumeClaimTemplates):
  apply the storage flip with `helm_wait=false`, then flip back.
- **Beyla label cardinality**: it stamps ~35 k8s attributes; Mimir's default
  `max_label_names_per_series=30` silently drops them — the hub raises it to 50.
- **Mimir OTLP config: verify every key/type against the running `/config`, never guess (ADR-100).**
  `promote_otel_resource_attributes` (note: **promote_otel**, not otel_promote) takes a **CSV
  string**, not a YAML/HCL list — the wrong shape doesn't error at plan time, it **crashloops every
  Mimir component** on apply (config parse failure). If that happens: `helm rollback mimir <last-good-rev>`
  immediately, then fix the config against `curl .../config` on a *working* Mimir. Also: even with
  `otel_keep_identifying_resource_attributes` + promoting `service.name`, OTLP-ingested series still
  break out per-service by **`job`** (`<team>-<product>/<svc>`) — Mimir does not surface `service_name`
  as a label for OTLP metrics the way it does for Beyla/remote-write ones. Query/dashboard/SLO/canary
  authors: group by `job`, not `service_name`, for an SDK-instrumented tenant service.
- **Manual `terragrunt apply` needs `AWS_PROFILE=management`** (bare shell assumes
  PlatformDeployer and 403s); reach the private API over Tailscale (ADR-010).
- **Per-team isolation (P13 / #590): write-split LIVE, read-proxy RETIRED (#1269), reads now SOFT.** Topology:
  the platform hub runs no team workloads, so its *own* metrics are the `platform` tenant; the real per-team
  tenants come from the **preprod spoke's live dual-write** (preprod runs the alpha/bravo apps). **Writes:**
  `cortex-tenant` write-splits each team's series into its own real Mimir/Loki tenant — LIVE. **Reads:** the
  hard fail-closed `tenant-proxy` (Mimir + `loki-tenant-proxy` for Loki; verified the SSO `X-Id-Token`, stamped
  `X-Scope-OrgID`, denied on missing token) was **built then retired (#1269)** — OSS Grafana's `oauthPassThru`
  can't reliably forward the token to a downstream proxy, so it fail-closed on `no_token` and blanked every
  dashboard. `read_proxy_url=""`; modules kept but inert, re-enableable if Grafana's token forwarding is fixed.
  Live read model is **soft**: per-tenant datasources (`Mimir (<team>)`, static `X-Scope-OrgID`) + **Grafana
  dashboard-folder permissions** + the namespace-filtered Team Overview dashboards (#1157). Cross-team sharing
  is soft too (share the dashboard/folder); the `AccessGrant` model (ADR-068) still governs cross-team access
  generally, but its fail-closed obs read-federation went with the proxy. **Traces (Tempo) + profiles
  (Pyroscope) per-team read scoping DEFERRED.** *(This block was itself stale until #1269 was reconciled —
  when in doubt on isolation status, check `read_proxy_url` in the live mimir/loki units, not this note.)*
- Mimir is **off** in the dev cost_profile; enabling it just starts `remote_write`
  (additive, no migration).

## References

- `docs/plans/102-observability-stack.md` — roadmap, architecture, per-phase checklists
- `docs/architecture/observability-current-state.md` — as-built status
- `docs/runbooks/observability-{alerts,instrumentation-verify,spoke-onboarding,troubleshooting}.md`
- `infra/modules/observability/{dashboards,alerts}/`, `infra/modules/observability-slo/`
- ADRs: 043/044 (self-hosted + Mimir), 076 (agent obs), 077 (instrumentation strategy)
