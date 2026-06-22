# observability-opencost (P11, part 1)

[OpenCost](https://www.opencost.io/) — in-cluster **cost allocation** (per namespace / workload / pod),
exposed as Prometheus metrics and viewable in Grafana. Part of **#102 P11** (cost). This is the
**in-cluster** half; the heavier **AWS CUR → Athena → Grafana** half (true cloud spend by `Team` tag) is a
separate follow-on.

## What it does

- A single exporter pod (~10m CPU) in the shared `observability` namespace.
- Queries the existing **kube-prometheus-stack Prometheus** (`opencost.prometheus.internal`) for node/pod
  resource usage, joins it with **on-demand node pricing from the public AWS pricing API** (no AWS creds
  needed), and emits cost-allocation metrics (`opencost_*` / `node_*`, `container_cpu/memory_allocation`,
  etc.).
- Its own metrics are scraped back into Prometheus via a **ServiceMonitor**, so per-namespace/workload cost
  is queryable in PromQL and dashboardable in Grafana.

## Cost & toggle

Cheap: one small pod, no standing cloud infra, no AWS API spend (public pricing). Gated by the
`enable_cost_metrics` cost_profile knob (`create`). On for the platform cluster.

Cloud-cost (`cloudCost`, CUR-based) is intentionally **off** — it needs a CUR + Athena setup (the P11 part-2
follow-on). For ad-hoc cloud spend today, the AWS console / Cost Explorer remains the source.
