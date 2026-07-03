# Cost Management Strategy

## Overview

Cost control on the platform combines **structural** defaults (the architecture bakes in
cheaper choices), **tag-based allocation** for visibility, **OpenCost** for near-real-time
per-team/per-namespace cost, and **AWS-bill-level monitoring** (Budgets, Cost Anomaly
Detection, CUR→Athena). The FinOps epic (ADR-092) and the per-team budget guardrails
(ADR-091) are live — see "Monitoring & governance" below. AWS is the only deployed cloud;
the same patterns extend to Azure/GCP.

## Cost allocation via tags

Every resource carries the standard tag set (see [Tagging Strategy](12-tagging-strategy.md)),
merged through `_base.hcl`. The cost-relevant keys:

| Tag | Use |
|-----|-----|
| `Environment` | Per-env spend (platform / preprod / prod) |
| `Team` / `Workload` | Per-environment / per-workload attribution (basis for showback) |
| `CostCenter` | Accounting group |
| `ComplianceTier` | Spend by tier (regulated tiers cost more) |

Each environment is also a **separate AWS account** (5 accounts), so account-level billing
already isolates spend before tags. Activate these as **cost allocation tags** in the
management account to break them out in Cost Explorer.

## Structural cost levers (in place)

| Lever | Where | Saving |
|-------|-------|--------|
| **Single NAT gateway** for non-prod | `single_nat_gateway = true` (networking unit) | ~$32/mo × (AZs−1) per VPC |
| **S3 gateway endpoints** on every VPC | networking module (free) | Keeps S3 traffic off the NAT data path |
| **Private-only EKS + internal NLB** | no public ALBs; ingress via Tailscale | Avoids public LB + data-egress |
| **Scale-to-zero off-hours** | node groups `desired=0` overnight | Nodes are the largest line item |
| **Small nodes** (`t3.large`) | node-group units | Right-sized for current load |
| **gp3 EBS** | launch template + StorageClass | Cheaper/faster than gp2 |
| **Custom PHZ cross-VPC DNS** | `dns_method` (not Resolver endpoints) | ~$365/mo avoided vs resolver endpoints |
| **SSE-S3 (not KMS) on high-churn buckets** | mimir/data buckets | No per-object KMS request cost |
| **Cilium overlay** | `cluster-pool` IPAM | Pods don't consume VPC IPs → no secondary-CIDR/larger-subnet cost |

## Major cost drivers (what to watch)

- **EC2 worker nodes** — the dominant cost; managed by node-group sizing + scale-to-zero.
- **EKS control plane** — ~$0.10/hr per cluster (platform + preprod).
- **NAT gateways** — hourly + per-GB; single-NAT for non-prod, S3 endpoint offload.
- **Transit Gateway** — per-attachment hourly + per-GB processed (hub + spokes).
- **EBS + S3** — node volumes, mimir/observability object storage, state bucket.
- **Data transfer** — cross-AZ and egress; minimized by keeping traffic in-VPC/in-region.

## Environment-specific optimization

- **preprod / non-prod** — single NAT, scale-to-zero off-hours, minimal node counts, no
  multi-AZ NAT redundancy.
- **platform (hub)** — runs shared services (ArgoCD, observability, TGW hub); sized for
  per-AZ coverage (system `desired=3`) which is a deliberate availability-over-cost call.
- **prod** — networking + org scaffolding only today (no cluster), so near-zero compute cost.

## Monitoring & governance

**OpenCost — near-real-time per-team allocation (live, both clusters, ADR-079 P11 pt.1).**
`infra/modules/observability-opencost` deploys a per-cluster OpenCost instance that derives
cost from in-cluster CPU/RAM allocation (`container_cpu_allocation` /
`container_memory_allocation_bytes`) joined against AWS On-Demand pricing
(`node_cpu_hourly_cost` / `node_ram_hourly_cost` — the public pricing API, no CUR needed).
This is the **speedometer**: fast feedback, no discount/RI/commitment awareness. The
platform (hub) instance queries its own in-cluster Prometheus; the preprod (spoke) instance
queries the hub Mimir externally (`prometheus_external_url`) since preprod has no queryable
in-cluster store. `cloudCost` (consuming the CUR/Athena true bill directly in OpenCost) is
**not** enabled yet — see CUR→Athena below.

- **Dashboards** — `team-cost.json` (hub only, deployed by the opencost module): total
  estimated monthly cost, cost by team (vs. each `Team.spec.envelope.budget.monthlyUSD`),
  cost by environment namespace, hourly burn-rate, and budget-utilization % with
  green/yellow/red thresholds. `platform-cost.json` (deployed by the main `observability`
  module) is the older infra-wide view: node cost, load-balancer cost, NAT-egress cost, cost
  by namespace.
- **Per-team budget guardrails (ADR-091, live, phased, audit-first):**
  - **Phase A (surface)** — OpenCost allocation visible in Grafana + Backstage.
  - **Phase B (alert)** — Mimir ruler burn-rate alerts at ≥80% of a team's monthly budget
    (Slack) and ≥100% (the team's own channel, via the ADR-084 owner-routing agent).
  - **Phase C (enforce, preprod only, audit-first)** — an hourly CronJob (in the
    `observability-opencost` module) queries the hub Mimir for each team's monthly-cost
    projection against `team_budget_monthly_usd` and writes over-budget teams to a
    `cost-budget-status` ConfigMap; a Kyverno ClusterPolicy reads it to deny new
    `XEnvironment` provisioning for teams over budget. Fails open if Mimir is unreachable.
- **AWS Budgets + Cost Anomaly Detection (live)** — `infra/modules/aws/cost-monitoring`
  provisions `aws_budgets_budget`, `aws_ce_anomaly_monitor` + `aws_ce_anomaly_subscription`,
  and an SNS topic wired to email + (optionally) an AWS Chatbot Slack channel. See
  [`cost-alerting.md`](../../docs/runbooks/cost-alerting.md) for setup/verification.
- **CUR → Athena — the true-spend odometer (Phase 1 live, management/payer account).**
  `infra/modules/aws/cost-export` delivers the Cost and Usage Report to S3, crawls it with
  Glue, and exposes it via Athena (workgroup `platform-cost-export`) — the authoritative
  AWS bill, `Team`-tag attributed, ~24h lag, capturing RI/Savings-Plan discount effects that
  OpenCost's live pricing can't. See [`cost-true-spend.md`](../../docs/runbooks/cost-true-spend.md).
  **Phase 2a** (OpenCost `cloudCost` consuming this via Athena) and **Phase 3** (dashboards
  on the true-spend data) are the still-deferred follow-on (#668).
- **Cost shift-left (live)** — Infracost runs in CI to surface a per-module cost diff on
  Terragrunt-unit PRs before apply. See [`cost-shift-left.md`](../../docs/runbooks/cost-shift-left.md).
- **Right-sizing** from observability remains a manual/ad-hoc practice today — the
  Prometheus/Mimir stack collects node/pod utilization, but there's no automated
  recommendation loop yet.
- **Savings Plans / Reserved Instances** once steady-state usage is established (currently
  all On-Demand; note the account's low On-Demand vCPU quota also bounds scale — see #168).

See also [ADR-091](../../docs/adrs/091-cost-guardrails.md) (per-team budget guardrails) and
[ADR-092](../../docs/adrs/092-platform-finops-practice.md) (the platform's own FinOps
practice, informing this doc's structure).

## Next Steps

Continue to [Region Scaffolding](20-region-scaffolding.md).
