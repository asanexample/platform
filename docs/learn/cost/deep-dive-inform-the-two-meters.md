# Learn: Cost & FinOps — Inform: the two meters (deep dive)

> Assumes the [Cost & FinOps orientation](orientation.md) — the **Inform → Optimize → Operate** loop, and the
> one-line version of Inform: *the platform runs **two** cost meters, because one number is a lie.* This deep
> dive stays inside **Inform** and takes those two meters apart: how each is actually computed, why there are
> two, and the handful of gotchas that bit us building them. If you just want the lookup, skip to
> [the Reference](reference.md).

The orientation gave you the anchor metaphor, and we'll lean on it the whole way down:

- **The speedometer — OpenCost.** Your *current rate* of spend, live, per team, but an **estimate at list
  price**.
- **The odometer — the CUR true-cost exporter.** The *actual distance travelled* — the real AWS invoice — but
  it **lags ~24h**.

House rule, restated: **trend on the speedometer, verdict on the odometer.** Now let's open each one up.

---

## Meter 1 — OpenCost, the speedometer

[OpenCost](https://www.opencost.io/docs/specification) is a CNCF in-cluster cost model. It does something
deliberately simple: for every pod, it multiplies **resource *allocation*** (the CPU-seconds and
memory-bytes the pod is reserving) by the **node's hourly price**, and rolls the result up by namespace, then
by team. That's the whole idea — `usage × price`, continuously.

The subtle, load-bearing word is **list price**. OpenCost prices nodes off the **public AWS pricing API** — no
AWS credentials needed for that path. The module makes this explicit:

```hcl
# infra/modules/observability-opencost/main.tf
# Node pricing (in-cluster allocation) uses the public AWS pricing API — no creds needed for that.
```

That's why the speedometer is *fast* (it updates every scrape, so a team whose burn just doubled shows up
**now**) and *blind to your bill's reality* (it knows nothing about Savings Plans, negotiated rates, or the
non-pod line items — NAT gateways, the EKS control plane, data transfer). It is an honest **estimate**, and
the orientation's rule about not confusing it with the invoice starts right here.

### Per-team, by *label* — not by name

The rollup to a team is the part people get wrong, so the dashboard is emphatic about it. A team is **not** the
namespace *name prefix* — it's the `platform.refplat.org/team` **label** on the environment namespace. The
`team-cost.json` panel query joins pod-cost to that label via `kube_namespace_labels`:

```promql
sum by (team) ( label_replace( label_replace(
  ( sum by (namespace) (
      (container_cpu_allocation * on(node) group_left() node_cpu_hourly_cost)
    + ((container_memory_allocation_bytes / 1024^3) * on(node) group_left() node_ram_hourly_cost)
    ) * 730
  ) * on(namespace) group_left(label_platform_refplat_org_team)
      max by (namespace, label_platform_refplat_org_team) (kube_namespace_labels),
  "team", "$1", "label_platform_refplat_org_team", "(.+)" ),
  "team", "platform", "team", "^$" ) )
```

Why the label and not the name? Because `kube-system`, `crossplane-system`, `external-dns` and every other
platform namespace *has* a name but is nobody's tenant. Keying on the prefix would mint a fake "team" for each
of them. Keying on the deliberate `team` label means **only real environment namespaces** roll up to a real
team — and everything unlabelled falls through to `platform` (that inner `label_replace(..., "team",
"platform", "team", "^$")` is the "empty team → platform" catch; hold that thought for [shared
cost](#shared-cost--the-slice-that-belongs-to-no-team)).

### One meter, both clusters

OpenCost runs on **both** the platform hub and the preprod spoke — verified live:

```text
# platform (hub)
opencost-…                2/2   Running
true-cost-exporter-…      1/1   Running

# preprod (spoke)
opencost-…                2/2   Running
# (no true-cost-exporter — see Meter 2)
```

The spoke has no queryable in-cluster Prometheus of its own (the durable metric store is the hub's Mimir), so
the module flips OpenCost to point at an **external** Prometheus endpoint — the hub Mimir's query API — via
`use_external_prometheus`:

```hcl
# main.tf — a spoke sets prometheus_external_url; the hub uses its in-cluster Prometheus.
use_external_prometheus = var.prometheus_external_url != ""
```

The important nuance the code comments call out: the dashboard reads OpenCost's **exporter metrics** (computed
from the k8s API + the pricing API and scraped into Prometheus), so cost still flows *even if* the allocation
query path is degraded. The speedometer keeps ticking.

> **Quick check:** if you rename an environment namespace but forget its `platform.refplat.org/team` label,
> where does its spend land on the by-team panel? *(Answer: rolled into `platform` — the empty-team catch — not
> onto the intended team. The label is the source of truth, not the name.)*

---

## Meter 2 — the true-cost exporter, the odometer

Now the authoritative half. The odometer answers "what did AWS *actually* bill?" — discounts, Savings Plans,
and all the non-pod cost OpenCost can't see. That data lives in the **Cost & Usage Report (CUR)**, and getting
it onto a Grafana panel took a small, purpose-built service. Two questions explain its whole shape.

### Why a *separate* exporter at all?

OpenCost has its own `cloudCost` pipeline that *can* read the CUR — and the module does wire it up. But there's
a wall, and the code comment is the primary source:

```hcl
# main.tf
# NOTE: OpenCost's cloudCost pipeline is NOT Prometheus-scrapeable (only its own /cloudCost REST
# API) — this wiring feeds OpenCost's own UI/API only. Grafana visibility is the separate
# true-cost-exporter below, which queries Athena directly.
```

So `cloudCost` populates OpenCost's *own* UI, but **nothing Grafana can scrape**. To land the true bill on a
Mimir-backed dashboard next to the estimate, the platform runs its own **~150-line Python exporter**
(`true-cost-exporter.tf`): it assumes the cross-account cost-reader role, runs SELECT-only Athena queries
against the CUR, and re-serves the results as Prometheus metrics on `:9105/metrics`.

It refreshes on a **timer, not per-scrape** — default `REFRESH_SECONDS = 21600` (6 hours). Querying Athena
every 30s would be pointless: the CUR data underneath only updates roughly daily, so the exporter caches a
rendered metrics file and re-serves it between refreshes.

The series it emits (from the source):

- `platform_true_cost_monthly_usd{breakdown="team|service|account",label="…"}` — this month's unblended spend,
  broken down three ways.
- `platform_true_cost_monthly_usd_total` — all-teams total for the month.
- `platform_true_cost_compute_monthly_usd_total` — EC2-only, the number you reconcile against OpenCost's
  node-price estimate.
- `platform_true_cost_exporter_last_success_timestamp_seconds` — a heartbeat, so a "data freshness (age)" panel
  can tell **stuck** apart from **just lagging**.

### Why is it hub-only?

The CUR is **org-wide** and generated by the **payer / management account** — a member account can't produce
it. So the odometer only needs to run *once*, on the hub, where it can reach the CUR via the cross-account
role. That's exactly what the live check above shows: `true-cost-exporter` exists on platform, `NotFound` on
preprod. One odometer for the whole platform; a speedometer per cluster.

---

## The CUR pipeline — where the odometer's data comes from

The exporter is the consumer; the data pipeline is a separate module in the **management/payer** account
(`infra/modules/aws/cost-export`, applied at `infra/live/aws/mgmt/global/cost-export/`, `us-east-1` — CUR is
payer-only and `us-east-1`-only). Every design choice here is a "we chose X not Y because Z" worth learning.

**Legacy CUR, *not* CUR 2.0 / Data Exports.** Deliberate:

```hcl
# aws/cost-export/main.tf
# Legacy CUR (not CUR 2.0 / Data Exports) on purpose: OpenCost's cloudCost Athena
# integration expects the documented legacy-CUR schema.
```

OpenCost's `cloudCost` expects the legacy schema, so the pipeline stays on the legacy
[CUR](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html) — Parquet, hourly, `+RESOURCES`
(resource IDs and the activated cost-allocation tags as columns), `OVERWRITE_REPORT` (required with the Athena
artifact; keeps storage flat).

**S3 with SSE-S3 (AES256), *not* KMS.** Also deliberate, and doubly so:

```hcl
# SSE-S3 (AES256), NOT SSE-KMS: the CUR service (billingreports.amazonaws.com)
# can't use the AWS-managed KMS key, and AES256 keeps the cross-account reader
# (OpenCost) free of kms:Decrypt.
```

Two independent reasons in one line: the billing service literally can't write to a managed-KMS bucket, *and*
AES256 spares the cross-account reader a `kms:Decrypt` grant it would otherwise need. (A customer-managed KMS
key is the regulated-tier upgrade, tracked separately.)

**Glue database + a *daily crawler*, then Athena.** The CUR's Parquet schema drifts month to month (AWS adds
columns), so instead of hand-defining a ~100-column table, a daily [Glue](https://docs.aws.amazon.com/athena/latest/ug/what-is.html)
crawler discovers the schema and partitions, with `delete_behavior = "LOG"` / `update_behavior =
"UPDATE_IN_DATABASE"` so it **adds** columns rather than recreating the table. An Athena workgroup
(`platform-cost-export`) then serves SQL over it. Hand-defining the table "would not survive CUR schema drift"
— the crawler is what makes the pipeline durable.

### The cross-account read — Pod Identity + the TagSession gotcha

The exporter runs on the platform hub but the CUR lives in the management account, so it crosses accounts. The
chain: an [EKS Pod Identity](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html) association
gives the `true-cost-exporter` ServiceAccount a role in the platform account, which then assumes the
management-account `cost_reader` role. And there's a real trap in that hop — the platform-side policy grants
**both** `sts:AssumeRole` *and* `sts:TagSession`:

```hcl
# main.tf — cost_reader_assumer policy
# TagSession, not just AssumeRole: the Pod-Identity-issued session already carries transitive
# session tags (added by pods.eks.amazonaws.com), and AWS requires TagSession permission on the
# target role to propagate them through a further AssumeRole call — confirmed live (#668):
# AssumeRole-only produced "not authorized to perform: sts:TagSession on resource: cost_reader".
Action = ["sts:AssumeRole", "sts:TagSession"]
```

**Session tags don't propagate through a further `AssumeRole` without `TagSession` permission on the target
role.** Pod Identity stamps transitive tags on the session; the second assume then *fails* with a
`sts:TagSession` denial unless the target role's trust and the caller's policy both allow it. Both sides of the
cost-reader trust carry the pair — this is the kind of thing a fresh reading of the happy path never reveals.

**The 24h first-delivery lag.** A newly created CUR's *first* file lands ~24h after creation. So immediately
after `apply`, the bucket, CUR definition, crawler, workgroup, and role all exist — but the Glue table doesn't
yet, and Athena returns nothing. This isn't a bug; it's the odometer being an odometer. The freshness panel
exists precisely so you can tell "waiting for the first delivery" from "the exporter is stuck".

---

## Per-team attribution — two independent join keys

Here's a symmetry worth naming: **the two meters attribute to a team by two entirely different mechanisms.**

- **OpenCost (speedometer)** joins on the in-cluster **`platform.refplat.org/team` namespace label** — see the
  PromQL above. Instant, but only sees *pod* cost.
- **The CUR exporter (odometer)** groups on the **activated `Team` cost-allocation tag** (#673) that AWS
  stamps onto CUR rows. Its Athena query:

  ```sql
  SELECT COALESCE(NULLIF(resource_tags_user_team, ''), 'untagged') AS label,
         SUM(line_item_unblended_cost) AS cost
  FROM <db>.<table> WHERE <this month> GROUP BY 1
  ```

Two things to internalise about the CUR tag. First, **`COALESCE(NULLIF(…,''),'untagged')`** — any CUR row
without a team tag is bucketed as `untagged` rather than dropped, so the total always reconciles and
unattributed spend is *visible*, not hidden. Second, the operational gotcha: activating a cost-allocation tag
is **forward-only** — ~24h to activate, and **no backfill**. Spend tagged before activation never gets the
column retroactively, so the tag was activated early on purpose.

---

## Shared cost — the slice that belongs to no team

A big share of a *small* platform's bill genuinely can't be pinned to a tenant: the EKS control planes, the
**NAT gateways** (a real big-ticket item), the Transit Gateway, the whole LGTM+P observability stack *and its
S3*, ArgoCD, Crossplane. FinOps calls this the **platform-shared Scope**, and
[ADR-092](../../adrs/092-platform-finops-practice.md) **D2** makes it a *first-class* thing:

> The platform-shared cost bucket is a first-class Scope, surfaced honestly — *allocate what is allocatable,
> show the rest plainly. It is never silently spread across tenant budgets.*

Socialising it would corrupt the very per-team signal you built the meters to produce. So both meters surface
it *as its own line*, never smeared across tenants:

- On the **speedometer**, the `label_replace(…, "team", "platform", "team", "^$")` you saw earlier is the
  mechanism: any namespace with no team label rolls up to an explicit **`platform`** bucket.
- On the **odometer**, untagged CUR rows land in the **`untagged`** bucket — the true-cost-by-team panel labels
  it exactly that, "real shared/platform infra spend not yet attributed to a team".

---

## Where teams actually see it

Three surfaces, and one honest "not yet":

- **`team-cost.json`** — "Cost — by Team & Environment (OpenCost)", provisioned as code on the **hub Grafana**,
  rendering OpenCost metrics fed from **both clusters**. Total estimated monthly cost, cost by team, cost by environment namespace, live hourly burn
  rate, and a budget-utilisation bar (spend ÷ the team's declared budget envelope — the Operate-phase
  guardrail, covered in [that deep dive](deep-dive-operate-guardrails-and-the-practice.md)).
- **`platform-cost.json`** — "Platform Cost", **live on the hub**, and the only place **both meters** sit
  together. Node/LB/NAT estimates *and* the CUR panels — true monthly spend, true cost by team / service /
  account, data-freshness age, and the money panel: **"OpenCost estimate vs CUR actual — compute
  ($/mo, reconciliation)"**, which plots `sum(node_total_hourly_cost) * 730` (list-price estimate) against
  `max(platform_true_cost_compute_monthly_usd_total)` (post-discount actual). A persistent gap between the
  lines *is* your discount — the reconciliation the orientation promised.
- **The Backstage cost tab — designed, *not* built.** [ADR-091](../../adrs/091-cost-guardrails.md) lists a
  developer-portal cost view as *remaining*, and ADR-092's capability table optimistically calls it "live" — but
  a grep of the `backstage` module finds **no cost plugin**. Treat it as roadmap. (This is a live example of
  the mold's rule: an ADR is a *lead*, the code is the *proof*.)

---

## Gotchas that teach

- **`max`, never `sum`, on the true-cost gauges (#668, commit `53dc4f65`).** The exporter's metrics carry a
  per-pod label, so **every exporter restart mints a fresh series**, and each pod reports the *same* monthly
  total. Aggregate with `sum` and during the brief pod-overlap window on a restart you count the same dollars
  twice; sum across historical pods and you count them many times. The fix is purely query-side: `max` (and
  `max by (label)`) collapses the identical per-pod copies to the one true value. It's a monthly *gauge*, not
  a counter — treat it like a thermometer reading, not a tally.
- **`sts:TagSession` on the second hop.** Pod-Identity sessions carry transitive tags; a further `AssumeRole`
  needs `TagSession` on the target role or it fails with `not authorized to perform: sts:TagSession`. Grant the
  pair on both sides.
- **AES256, not KMS, on the CUR bucket.** The billing service can't write to a managed-KMS bucket, and AES256
  keeps the cross-account reader free of `kms:Decrypt`.
- **Legacy CUR, not CUR 2.0.** OpenCost's `cloudCost` expects the legacy schema; a CUR 2.0 / Data Export would
  silently not line up.
- **`python3 -u` (unbuffered).** Without it, Python block-buffers stdout when not on a tty, so the refresh
  logs never appear in `kubectl logs` even though the exporter is working (confirmed live, #668). A "silent but
  healthy" pod is the most confusing kind.
- **The ADRs undersell the status.** ADR-091 and ADR-092 still describe the CUR→Athena true-cost work (#668)
  as **"unbuilt"** and the cost-allocation tag (#673) as **"not applied"**. Both are **stale** — #668 is built
  and running (the pods above, the merged reconciliation dashboard), and the `Team` tag is active. Primary
  source beats secondary source; the ADR text is the lead, the cluster is the truth.

---

## Go deeper

- **The orientation** — [Cost & FinOps](orientation.md) (the loop this deep dive lives inside), then the
  siblings: [Optimize — the cost levers](deep-dive-optimize-the-cost-levers.md) and [Operate — guardrails &
  the practice](deep-dive-operate-guardrails-and-the-practice.md).
- **Source of truth (code):**
  [`observability-opencost/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-opencost/main.tf)
  (the speedometer + the Pod-Identity/TagSession wiring),
  [`true-cost-exporter.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/observability-opencost/true-cost-exporter.tf)
  (the odometer),
  [`aws/cost-export/main.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/aws/cost-export/main.tf)
  (the CUR pipeline),
  [`dashboards/platform-cost.json`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/dashboards/platform-cost.json)
  (both meters + reconciliation).
- **ADRs & runbook:** [ADR-091](../../adrs/091-cost-guardrails.md) (tenant Scope + attribution join, D2),
  [ADR-092](../../adrs/092-platform-finops-practice.md) (the platform-shared Scope, D2/D3), and
  [`docs/runbooks/cost-true-spend.md`](../../runbooks/cost-true-spend.md) (apply + the day-after verification of
  the CUR pipeline).
- **External substrate** (all official, verified reachable):
  - [OpenCost — AWS configuration](https://www.opencost.io/docs/configuration/aws) — how the model prices AWS
    nodes and the `cloudCost` integration (~10 min).
  - [OpenCost — specification](https://www.opencost.io/docs/specification) — the `usage × price` allocation
    model in full (~15 min).
  - [AWS — What is the Cost & Usage Report](https://docs.aws.amazon.com/cur/latest/userguide/what-is-cur.html)
    — the legacy-CUR schema the pipeline depends on (~10 min).
  - [AWS — passing session tags](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_session-tags.html) — why
    the second `AssumeRole` needs `TagSession` (~5 min).
</content>
