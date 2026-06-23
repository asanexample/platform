# observability-k6

**Scripted synthetics** (#102 P9b / k6) — the second half of P9b alongside the blackbox-exporter. A **k6
CronJob** runs scripted multi-target checks with **pass-rate + latency thresholds** and exports its metrics to
**Mimir** (Prometheus remote_write). Where blackbox does simple external availability/TLS probes, k6 adds
scripted checks (content assertions, multi-step flows) and richer metrics (`k6_http_req_duration` percentiles,
`k6_checks` pass-rate).

## What it deploys

- A **ConfigMap** with the k6 script (`scripts/checks.js`) — checks the in-cluster store/UI health endpoints
  (Grafana `/api/health` + DB-ok assertion, Mimir/Loki/Tempo `/ready`). In-cluster targets, so there's no
  internal-NLB hairpin and no NetworkPolicy change (intra-namespace).
- A **CronJob** (`grafana/k6`) running on a schedule; a breached threshold exits non-zero (a failed Job,
  visible + alertable). Metrics → Mimir under `tenant_id`, via `K6_OUT=experimental-prometheus-rw` +
  `K6_PROMETHEUS_RW_HTTP_HEADERS=X-Scope-OrgID:<tenant>`.

## Metrics

`k6_checks` (pass/fail rate per `target`), `k6_http_req_duration` (p95/p99/avg), `k6_http_reqs`, … — build
SLOs/alerts on them. Edit `scripts/checks.js` to add targets or multi-step user journeys.
