# ADR-079: Cloud-Resource Monitoring Scope — Query-Time-First in Grafana

**Status:** Accepted — P5a (Grafana CloudWatch metrics + Logs datasource) and P5b (YACE → Mimir) built + live on the platform hub; curated AWS dashboards/alerts and the scope descopes below are the outstanding work (2026-06-24)

> Amendment (2026-06-30, #668): the true-cloud-cost **CUR → Athena** pipeline (D4, P11 pt 2) Phase 1 is built — the `aws/cost-export` module (legacy CUR → S3 → Glue → Athena + cross-account read role) in the payer account. Consumption via OpenCost `cloudCost` (Phase 2a) + dashboards (Phase 3) remain. See `docs/runbooks/cost-true-spend.md`.

## Context

[ADR-043](043-self-hosted-observability-stack.md) decided the observability *backbone* and
`docs/plans/102-observability-stack.md` built out the in-cluster halves — metrics, logs, traces, profiles,
alerting, in-cluster cost. The **cloud-resource** half (visibility *beyond* the cluster — the AWS services
the platform itself runs on) was named as P5 but never had its scope nailed down, and a review raised the
fair question: is the thin AWS coverage intentional?

It is *partly* built and was never fully scoped. Taking stock of what actually exists:

- **P5a is live** — the Grafana **CloudWatch datasource** is provisioned on the hub
  (`cloudwatch_enabled = true`), and the Grafana ServiceAccount holds a Pod-Identity role granting CloudWatch
  **metrics** read *and* CloudWatch **Logs Insights** read (`infra/modules/observability/main.tf`). One
  datasource covers both metrics and log queries, query-time, zero storage.
- **P5b is live** — the YACE / `cloudwatch-exporter` unit scrapes a **curated** set
  (`AWS/NetworkELB`, `AWS/NATGateway`, `AWS/TransitGateway`) into Mimir for alerting/PromQL.
- **P5c (CloudWatch Logs → Loki via Firehose) is unbuilt**, and **true cloud cost** (CUR → Athena) is the
  unbuilt P11 part 2. **GuardDuty / AWS Config are not enabled** anywhere.

A footprint count from the live configs frames the decision: **0 RDS / Aurora** (Postgres is CloudNativePG,
in-cluster), **0 ALBs** (the 2 load balancers are NLBs, already in the YACE set), 3 NAT gateways, 1 Transit
Gateway, 2 EKS clusters, ~3 baseline nodes. The monitorable AWS metric universe is *small* — low hundreds of
metrics — and the usual cost-drivers (RDS fleets, ALB target groups) are absent. This ADR decides the scope
and the cost model for completing cloud-resource monitoring; it does not redesign the backbone.

## Decision

Adopt a **query-time-first** model for cloud-resource observability in Grafana: **query CloudWatch live for
breadth, store only the metrics that back an alert.** Complete cost visibility via CUR → Athena. Descope
Loki log ingestion to a need-driven exception, and **punt AWS-native security/compliance services
(GuardDuty, Config)** as a separate decision.

The guiding principle: *the cost trap in AWS monitoring is `GetMetricData` polling and Loki/Mimir storage —
so pay to store only what pages someone, and query the rest on demand.*

## Design

### D1 — Query-time CloudWatch datasource is the breadth layer (P5a, live)

The Grafana CloudWatch datasource is the default for AWS-resource metrics *and* logs: RDS / ELB·NLB / SQS·SNS
/ Transit Gateway / Route53 / ACM / NAT / EKS, plus CloudWatch Logs Insights over the VPC-flow-log and
CloudTrail groups — **no exporter, no storage**. Auth is the Grafana ServiceAccount's Pod-Identity role
(ADR-047), already granting the standard read set (`cloudwatch:GetMetricData`/`ListMetrics`/…,
`logs:StartQuery`/`GetQueryResults`/…, `tag:GetResources`, `ec2:Describe*`). Grafana is hub-only (one pane on
the platform cluster), so this needs no per-spoke replication. **Remaining P5a work is curated AWS dashboards,
not plumbing.**

### D2 — Store only the alert-backing subset (P5b, live)

YACE → Mimir stays scoped to the metrics we alert and always-on-dashboard on (today NLB / NAT / Transit
Gateway). New namespaces are added **only when a metric backs an alert** — and notably **nothing new is
warranted by the current footprint**: there is no RDS, and the NLBs are already covered. Expansion is a
deliberate per-metric decision, not a blanket scrape.

### D3 — CloudWatch Logs → Loki is descoped to a need-driven exception (was P5c)

The query-time CloudWatch Logs datasource (D1) already makes VPC-flow logs and CloudTrail queryable in
Grafana — they are *already ingested into CloudWatch Logs* by the networking and cloudtrail modules, so the
visibility is essentially free on spend already incurred. We therefore **do not build the Firehose →
Alloy → Loki pipeline** as general scope. A specific log group is shipped to Loki **only** when it must back
a Loki-side alert or long-retention cross-signal correlation. **VPC flow logs are explicitly excluded from
Loki** (highest-volume, lowest-marginal-value — query them in place).

### D4 — True cloud cost = CUR → Athena → Grafana (P11 part 2)

Real AWS spend (including RDS/S3/data-transfer that in-cluster OpenCost cannot see) comes from a **Cost &
Usage Report / Data Export → Athena → Grafana Athena datasource**, attributed by the `Team` tag. OpenCost
stays the in-cluster per-namespace allocator (P11 part 1, live). The Athena datasource ships bundled in
Grafana OSS (no plugin/licence). CUR data is small for this org — Athena scan cost is cents.

### D5 — Cost guardrails for the query-time model

Query-time shifts cost from storage to API calls, so we bound the API calls:

- **Dashboard auto-refresh floor ≥ 1m** (default longer); avoid leaving broad CloudWatch dashboards open on
  fast refresh — this is the single thing most likely to inflate `GetMetricData`.
- **EKS control-plane logs stay OFF** (the live config already disables them; audit/api streams were cited at
  ~$700/mo across dev clusters). Turn on per-cluster, temporarily, only to debug.
- **Escape hatch:** if YACE polling cost ever climbs with scale, switch the stored tier to **CloudWatch
  Metric Streams → Firehose → Alloy → Mimir** (push, ~$0.003/1k vs $0.01/1k polled). Not warranted at the
  current footprint.

Estimated incremental run cost at the current footprint: **~$20/month** (mostly the already-deployed
datasource's query usage + CUR/Athena), versus the ~$30–110/month that GuardDuty + Config would add — which
is why those are a separate call (D6).

### D6 — AWS-native security/compliance services are punted (GuardDuty, Config)

GuardDuty and Config are **out of scope** for this monitoring effort. They are billed *services* (not
monitoring of existing resources), they materially exceed the rest of cloud monitoring combined, and turning
them on is a **security/compliance** decision — the natural home is [ADR-055](055-compliance-assurance-and-continuous-control-evidence.md)
(continuous control evidence), not here. When they are adopted, their findings ride the **existing** path:
EventBridge → SNS → the Alertmanager SNS receiver already wired in the observability module — no new
ingestion infra. (AWS Health / Personal Health Dashboard events route the same way if wanted.)

## Dependencies & sequencing

- D1/D2 are **done and live**; the near-term work is **curated AWS dashboards** (D1) + **one or two
  cloud-resource alerts** off the YACE/Mimir metrics (D2) to satisfy the P5 verify bar.
- D4 (CUR → Athena → Grafana) is the one genuinely new build — a small AWS unit (CUR/Data Export + Athena
  workgroup/Glue) plus an `additionalDataSources` Athena entry and a read role; folds into P11.
- D3/D6 are **scope decisions** — no build unless a named need arises.
- Rides the existing Grafana/Pod-Identity (ADR-047) and SNS-alerting plumbing; no new backend.

## Consequences

- **+** Broad AWS metric *and* log visibility in Grafana for ~zero fixed cost — the breadth layer is already
  shipped; flow-log/CloudTrail visibility is free value on spend already incurred.
- **+** Storage and `GetMetricData` cost stay bounded — store only alert-backing metrics; query the rest.
- **+** No speculative pipelines — the Firehose→Loki path is built only against a named need, not by default.
- **+** Honest, recorded scope — the "thin AWS coverage" is now a deliberate, costed decision, not an
  oversight.
- **−** Query-time dashboards are slower than stored ones and have no retention beyond CloudWatch's own
  (~15 months); anything we want to alert on or keep long-term must be promoted to D2 (stored).
- **−** No proactive threat-detection / config-drift posture until GuardDuty/Config are taken up separately
  (D6) — an accepted gap, owned by the compliance track.

## Alternatives considered

- **Scrape everything into Prometheus/Mimir** — rejected. Continuous `GetMetricData` polling of the full
  namespace set plus Mimir storage is the classic AWS-monitoring cost surprise, for breadth a human looks at
  occasionally. Query-time gives the same breadth without the standing bill.
- **Ship all AWS logs (incl. VPC flow) to Loki for a single pane** — rejected as default scope (D3). Flow
  logs are high-volume; the query-time CloudWatch Logs datasource already surfaces them in Grafana, and
  they're already in CloudWatch Logs.
- **A SaaS cloud-monitoring integration (Datadog / New Relic CloudWatch)** — rejected; against the
  self-hosted, OSS-default principle of [ADR-043](043-self-hosted-observability-stack.md). The OSS datasources
  cover it.
- **Enable GuardDuty + Config now as part of monitoring** — rejected (D6); a billed-service security decision
  that dwarfs the monitoring cost, belongs to the compliance track, and isn't required for resource
  visibility.

## Related

- [ADR-043](043-self-hosted-observability-stack.md) — the observability backbone this rides.
- [ADR-044](044-mimir-durable-multi-tenant-metrics.md) — the durable metric store the P5b subset lands in.
- [ADR-047](047-pod-identity-as-aws-identity-standard.md) — the Pod-Identity pattern the Grafana CloudWatch
  read role uses.
- [ADR-055](055-compliance-assurance-and-continuous-control-evidence.md) — the home for any future
  GuardDuty/Config (D6) adoption.
- `docs/plans/102-observability-stack.md` — P5 (cloud-resource observability) and P11 (cost); issue
  [#102](https://github.com/asanexample/platform/issues/102).
