# observability-cloudwatch-exporter (P5b)

YACE — [yet-another-cloudwatch-exporter](https://github.com/prometheus-community/yet-another-cloudwatch-exporter) —
scrapes **AWS CloudWatch** metrics and exposes them as **Prometheus** metrics, so the platform's
cloud-resource state is queryable/alertable in PromQL alongside cluster metrics. Part of **#102 P5**
(cloud-resource observability); complements the query-time Grafana **CloudWatch datasource** (P5a) with the
durable, alertable subset.

## What it does

- A single Deployment (1 replica — multiple would double-scrape CloudWatch and double the API cost) in the
  shared `observability` namespace, scraped by the kube-prometheus-stack Prometheus via a **ServiceMonitor**.
- **Tag-based discovery** of the platform's always-on network resources (5-minute period):
  - `AWS/NetworkELB` — the internal gateway NLB(s): healthy/unhealthy host count, flows, processed bytes.
  - `AWS/NATGateway` — port-allocation errors, packet drops, egress bytes.
  - `AWS/TransitGateway` — bytes in/out, blackhole drops.
  - (S3/storage daily metrics are intentionally omitted — different period, little operational value here;
    broad ad-hoc coverage is the P5a CloudWatch datasource's job.)
- Metric names are emitted as `aws_<namespace>_<metric>_<stat>` (e.g. `aws_networkelb_un_healthy_host_count_maximum`).

## Auth

CloudWatch read via **EKS Pod Identity** (ADR-047) — the role trusts `pods.eks.amazonaws.com`; **no IRSA
annotation**. Read-only: `cloudwatch:GetMetricData`/`GetMetricStatistics`/`ListMetrics`, `tag:GetResources`,
and `ec2:DescribeTransitGatewayAttachments`/`DescribeRegions` for discovery. `GetMetricData`/`ListMetrics`
don't support resource scoping, so `Resource = "*"`.

## Toggle

Gated by the `enable_cloud_metrics` cost_profile knob (`create`). On for the platform cluster; off by default
in `dev`. Extend `local.yace_config.discovery.jobs` to scrape more namespaces (add the matching describe
permission if the namespace needs one).
