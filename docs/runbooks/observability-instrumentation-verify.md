# Verifying zero-code instrumentation (Beyla RED + traces)

How to confirm the P7 instrumentation on-ramp (#586, ADR-077) actually works: an **un-instrumented**
workload emits **RED metrics** (Rate/Errors/Duration) + **traces** with **no code change**, via **Grafana
Beyla** (eBPF). Covers the hub (platform) and the preprod spoke.

## What's running

| Cluster | Beyla instruments | Traces path | RED metrics path |
|---------|-------------------|-------------|------------------|
| **platform** | `{backstage,keycloak,argocd,observability}` | Beyla → hub OTel collector → Tempo (tenant `platform`) | Beyla `/metrics` → ServiceMonitor → Prometheus → Mimir (`platform`) |
| **preprod** | `{alpha-*}` (the demo apps) | Beyla → preprod traces-spoke collector → hub Tempo edge → Tempo (tenant `preprod`, `cluster=preprod`) | Beyla `/metrics` → ServiceMonitor → preprod metrics agent → Mimir (`preprod`) |

Gated by `enable_instrumentation` (platform + preprod `env.hcl`). The **SDK opt-in** layer (OTel Operator
`Instrumentation` CR, annotation-driven) is **deferred to P14** — only the zero-code eBPF baseline is active.

## Verify — Beyla is running

```bash
kubectl --context <platform|preprod> -n observability get pods -l app.kubernetes.io/name=beyla   # DaemonSet, 1/node Ready
```

## Verify — RED metrics (Grafana)

- Open **Grafana → Dashboards → Platform Services APM/RED** (`platform-apm`).
- For preprod, switch the datasource to **`Mimir (preprod)`** (or `Mimir (all clusters)` to see both).
- Panels populate from `http_server_request_duration_seconds_*` once the instrumented services receive
  traffic. (Hit a service — e.g. open Grafana/ArgoCD on the hub, or curl an `alpha-*` app on preprod — to
  generate requests.)
- Quick PromQL check (Explore, `Mimir (preprod)`):
  `sum by (service_name) (rate(http_server_request_duration_seconds_count{cluster="preprod"}[5m]))`

## Verify — traces (Grafana / Tempo)

- **Grafana → Explore → `Tempo (preprod)`** (or `Tempo (all clusters)`) → search. Spans appear with
  `service.name` from the instrumented workloads and `cluster=preprod`.
- Or query the store directly:

  ```bash
  # hub Tempo, tenant preprod — any trace in the last 15m
  kubectl --context platform -n observability port-forward svc/tempo-query-frontend 3200:3200 &
  curl -s -H "X-Scope-OrgID: preprod" \
    "http://localhost:3200/api/search?q=%7B%20resource.cluster%3D%22preprod%22%20%7D&limit=5"
  ```

- **Trace ↔ logs**: a span's `service.name` links to its pod's logs (the Tempo datasource `tracesToLogsV2` →
  Loki), and a `trace_id` in a log line links back (the Loki `derivedField`).

## Troubleshooting

- **No spans / no RED for a service:** Beyla only emits for **observed HTTP/gRPC traffic** — an idle service
  produces nothing. Generate traffic. Confirm the service's namespace matches the Beyla `instrument_namespaces`
  glob (`kubectl -n observability get cm beyla-config -o yaml | grep -A3 discovery`).
- **Beyla pod CrashLoop / permission errors:** eBPF needs the **privileged** PSA namespace + host access — the
  `observability` namespace is created privileged by the metrics module; confirm the label is set.
- **Traces missing on preprod but present on hub:** check the preprod traces-spoke collector is Running and
  exporting (it forwards to `preprod-traces.aws.refplat.org`); see
  [observability-spoke-onboarding.md](observability-spoke-onboarding.md).
- **RED metrics missing on preprod:** the preprod metrics agent must scrape Beyla's ServiceMonitor — confirm
  `kubectl --context preprod -n observability get servicemonitor` lists the Beyla monitor.
- **RED scraped (target UP) but absent from Mimir:** Beyla stamps ~35+ k8s attributes per series, over Mimir's
  default `max_label_names_per_series` (30) → the series are **silently discarded** at ingest. Check
  `cortex_discarded_samples_total{user="<tenant>",reason="max_label_names_per_series"}` (query it under the
  **`platform`** meta-tenant, where Mimir's self-metrics live). The hub Mimir raises the limit to 50
  (`observability-mimir` `max_label_names_per_series`) to admit Beyla's label-rich series.
