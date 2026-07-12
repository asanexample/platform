# ADR-100: One instrumentation golden path + one metric convention (OTLP↔Prometheus convergence)

**Date:** 2026-07-12

**Status:** Accepted

## Context

The observability stack (OTel Collector + Grafana Alloy + LGTM+P + Beyla) is a standard reference
architecture, but it grew **two overlapping ways to produce the same signals**, and that overlap — not the
number of components — is where the operational pain lives.

**Two instrumentation sources.** A workload's RED metrics + traces can come from either:

- the **app's OpenTelemetry SDK** (the paved-road pattern — e.g. alpha-shop's `internal/telemetry`: traces +
  metrics + Pyroscope profiles + trace-stamped structured logs), exported OTLP → collector; or
- **Beyla** (eBPF auto-instrumentation) + the prometheus-agent, which need zero app code.

They **conflict** (Beyla's eBPF context-propagation overwrote the SDK's `traceparent`, fragmenting traces —
we already had to exclude SDK'd workloads from Beyla) and they **diverge on convention** (below).

**Two metric conventions reach Mimir for the *same* HTTP RED histogram:**

| Path | Ingest | Metric name | Service label | Namespace label |
|---|---|---|---|---|
| App OTel SDK | OTLP `/otlp/v1/metrics` | `http_server_request_duration` (no unit suffix) | `job` (`<svc.ns>/<svc.name>`) | *(none by default)* |
| Beyla / kube-state | remote-write `/api/v1/push` | `http_server_request_duration_seconds` | `service_name` | `k8s_namespace_name` |

Everything downstream — dashboards, SLO recording rules, the ADR-056 canary metric-gate, burn-rate alerts —
was written for the **remote-write** convention. App-SDK metrics arrive in the **OTLP** convention. That one
mismatch silently broke the alpha-shop dashboard, the canary success-gate, **and** the SLOs (their
`k8s_namespace_name`-filtered SLI produced no data, so burn-rate alerting and the canary budget-freeze gate
were inert) — each surfacing as a separate "bug" with the same root cause.

## Decision

**1. SDK-first is the golden path; Beyla is a zero-touch fallback — never both on one service.**
Instrumented workloads carry the OTel SDK (the `internal/telemetry` shape) and are excluded from Beyla. Beyla
covers only *un*-instrumented workloads (legacy / third-party). One canonical source per service — no
double-counting, no `traceparent` fight.

**2. Converge the convention at the storage layer, not per-query.** Mimir's OTLP ingest is configured to emit
the Prometheus convention, so OTLP-ingested metrics are indistinguishable from remote-write ones and a single
PromQL works regardless of delivery path (`infra/modules/observability-mimir`, per-tenant `limits`):

```hcl
otel_metric_suffixes_enabled              = true   # …_seconds / …_total
otel_keep_identifying_resource_attributes = true
promote_otel_resource_attributes          = "service.name,service.namespace,k8s.namespace.name,k8s.pod.name,k8s.deployment.name,k8s.node.name"  # CSV string
```

Result: OTLP series become `http_server_request_duration_seconds_*{k8s_namespace_name, job, http_route,
http_response_status_code, …}`. Dashboards/SLOs/canary now filter on `k8s_namespace_name` uniformly.

## Consequences

- Downstream is convention-agnostic: the shop dashboard, canary gate, and SLO rules all query
  `http_server_request_duration_seconds_*{k8s_namespace_name=…}` — one shape, whatever the source.
- **Per-service label differs by source:** OTLP uses `job` (`alpha-shop/shop-storefront` — the OTel service
  identifier; Mimir will *not* also surface it as `service_name`, so promoting `service.name` is a no-op for
  the label), remote-write uses `service_name`. Namespace-scoped queries are identical; per-service breakouts
  pick `job` for SDK'd services. Acceptable; documented here so it isn't re-discovered as a bug.
- ⚠️ **Mimir config keys/types must be verified against the *running* binary's `/config`, never guessed.** A
  first attempt guessed `otel_promote_resource_attributes = [list]`; the real key is
  `promote_otel_resource_attributes` and its value is a **CSV string** — the wrong form crash-looped every
  Mimir component (recovered via `helm rollback`). The apply is slow (multi-component `helm_wait`): run it
  from a warm env in the background and watch pods stay `Running`.
- Only OTLP-ingested series are affected; remote-write (Beyla/kube-state) is untouched. Extra promoted labels
  stay within the raised `max_label_names_per_series`.

## Alternatives considered

- **Patch each query to the OTLP-native names/labels** (job, no suffix). Rejected: leaves two conventions
  live, so the next dashboard/SLO/alert re-hits the same wall. (Used only as the temporary stop-gap.)
- **Keep two conventions, document both.** Rejected: every consumer must special-case delivery path.
- **Beyla-only** (drop app SDKs). Rejected: loses SDK-only signals (custom spans/metrics, the full Go profile
  suite, precise trace context) — the paved-road value.
- **SDK-only** (drop Beyla). Rejected: Beyla is the valuable zero-touch net for workloads that can't/ won't
  instrument; keep it, just scoped to those.

## Related

- ADR-056 (progressive delivery / metric-gated canary), ADR-077 (app instrumentation), ADR-099 (flagship).
- `reference_telemetry_correlation_complete` (the LGTM+P correlation hops), P10/P14 (preprod metrics spoke).
