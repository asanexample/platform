---
description: List the alerts currently firing across the clusters (via the Grafana MCP)
---

# Firing alerts

Using the **`grafana`** MCP, show what's firing across the platform/preprod clusters.

1. Run an instant PromQL query `ALERTS{alertstate="firing"}` against the **`mimir-all`** datasource
   (it federates all clusters). If `mimir-all` 502s/errors, fall back to the per-cluster `mimir`
   (platform) and `mimir-preprod` datasources.
2. Group results by `severity` and `cluster`, de-duplicating multi-series alerts (same `alertname`).
3. Flag **`Watchdog`** (severity `none`) as **always-firing by design** — a dead-man's-switch that
   proves alerting works; it is not an incident.
4. Call out anything `critical`/`warning` worth attention, and offer to root-cause it via Loki
   (`query_loki_logs`) — e.g. a parked-cluster pattern (CPUOvercommit, TargetDown, failed synthetics)
   vs. a real problem.

Keep it concise: a table of firing alerts with severity + what/where.
