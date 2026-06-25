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
3. `terragrunt apply` the observability unit → the ConfigMap is created and the sidecar
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
  labels: { severity: critical }     # critical→SNS+Slack+PagerDuty, warning→Slack, info→dashboard-only
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

## Instrument a workload (ADR-077, three layers)

- **Layer 0 — Beyla eBPF (automatic, zero code)**: a DaemonSet emits RED metrics
  (`http_server_request_duration_seconds_*`) + service graph + request traces for
  workloads in the scoped `discovery.instrument` namespaces. No app change, all
  languages. Verify per `docs/runbooks/observability-instrumentation-verify.md`.
- **Layer 1 — OTel Operator SDK inject (opt-in)**: annotate the workload
  `instrumentation.opentelemetry.io/inject-<lang>: "observability/platform"`; the
  operator injects the SDK + the platform-provided OTLP endpoint (never hardcode it) and
  adds code-level spans on top of Beyla. The per-namespace `Instrumentation` CR rollout
  is the P14 golden path.
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
- **Secrets**: all named `platform/*` (ESO IRSA scoped there) — Grafana admin/OIDC, Slack
  webhook, PagerDuty key.
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
- **Manual `terragrunt apply` needs `AWS_PROFILE=management`** (bare shell assumes
  PlatformDeployer and 403s); reach the private API over Tailscale (ADR-010).
- **Per-team read isolation (P13 / #590) is DESIGNED but PAUSED** — today everyone sees
  all clusters via the federated datasource. Don't assume tenant read-scoping exists yet.
- Mimir is **off** in the dev cost_profile; enabling it just starts `remote_write`
  (additive, no migration).

## References

- `docs/plans/102-observability-stack.md` — roadmap, architecture, per-phase checklists
- `docs/architecture/observability-current-state.md` — as-built status
- `docs/runbooks/observability-{alerts,instrumentation-verify,spoke-onboarding,troubleshooting}.md`
- `infra/modules/observability/{dashboards,alerts}/`, `infra/modules/observability-slo/`
- ADRs: 043/044 (self-hosted + Mimir), 076 (agent obs), 077 (instrumentation strategy)
