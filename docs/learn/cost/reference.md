# Learn: Cost & FinOps — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
live. Dollar figures, account IDs, and the personal alert address are intentionally omitted — mechanism only.

## The loop (FinOps Foundation Framework — [ADR-092](../../adrs/092-platform-finops-practice.md))

**Inform → Optimize → Operate**, run iteratively; maturity tracked Crawl→Walk→Run. **Scopes:**
`platform-shared` (control planes, NAT/TGW, observability + its S3, ArgoCD/Crossplane — surfaced, never
socialized), `per-team/tenant` (= ADR-091), and `AI/GenAI` (emerging, not built). Principle: **free OSS +
AWS-native only; no vended cost SaaS, ever.**

## Inform — the two meters ([deep dive](deep-dive-inform-the-two-meters.md))

| | **OpenCost** (speedometer) | **true-cost-exporter** (odometer) |
| --- | --- | --- |
| Measures | in-cluster **allocation estimate** (usage × **list price**) | **actual AWS bill** (CUR — sees discounts/SP/RI + non-pod cost) |
| Freshness | near-real-time (current *rate*) | **lags ~24h** (monthly *verdict*) |
| Attribution | `platform.refplat.org/team` namespace label | activated **`Team` CUR cost-allocation tag** (#673) |
| Blind to | discounts, NAT/control-plane/data-transfer/EBS/S3 | live rate (only a daily total) |
| Module | `observability-opencost/main.tf` (both clusters) | `observability-opencost/true-cost-exporter.tf` (hub) |

House rule: **trend on OpenCost, verdict on the CUR.** The `platform-cost.json` dashboard shows both + an
estimate-vs-actual reconciliation panel.

- **#668 max-not-sum:** true-cost is a **monthly gauge** re-emitted every scrape → `sum()` double-counts;
  aggregate with **`max`** (`max(platform_true_cost_monthly_usd_total)`). Commit `53dc4f65`.
- **The CUR pipeline** (module `aws/cost-export`, **mgmt/payer account**, us-east-1): legacy CUR (not CUR 2.0 —
  OpenCost cloudCost expects legacy schema) → S3 (**AES256** not KMS — billingreports can't use the managed
  key) → Glue db + daily crawler → Athena workgroup → cross-account **`cost_reader`** role. The hub exporter
  assumes it via **Pod Identity** — needs `sts:AssumeRole` **+ `sts:TagSession`** (session tags don't
  propagate through a further AssumeRole without it). First CUR delivery ~24h after create.
- **Shared/unallocable cost** (ADR-092 D2): EKS control planes, **NAT gateways** (big-ticket), TGW, LGTM+P +
  its S3, ArgoCD/Crossplane → rolled up to a `platform` bucket (`label_replace(..., "team","platform","team","^$")`),
  never split into fake per-team cost.

## Optimize — the levers ([deep dive](deep-dive-optimize-the-cost-levers.md))

- **Karpenter** (`aws/karpenter`, [ADR-078](../../adrs/078-cluster-elasticity-karpenter.md)): JIT nodes sized
  to pending pods + **consolidation** (bin-pack + terminate underutilized). Per-cluster: **hub =
  on-demand-only + `WhenEmpty`** (stateful singletons — a spot reclaim would disrupt data); **preprod =
  `["spot","on-demand"]` + `WhenEmptyOrUnderutilized`**. **"Spot retired" = only the static managed spot
  *group*; spot capacity-type is live on preprod.** Gotchas: **min 8 GiB node floor** (`min_instance_memory_mib
  = 6144`; DaemonSet slab ~3.2 GiB); **SCP exemption mandatory** (`<cluster>-eks-karpenter-*` — anchored
  per-cluster, not a leading-wildcard — in `exempt_roles`, or DenyTeamTagTampering/require-tagging 403 every
  launch); BYOCNI `node.cilium.io/agent-not-ready` startup taint.
- **Cluster parking** (`platctl down/up`, `cluster-parking` skill): node groups → **`desiredSize=0`** overnight;
  **non-destructive** (control plane + EBS/CNPG preserved); reversible. Judge a park via the **EKS API, not
  kubectl** (parking drops the Tailscale router); unpark = fresh pod admission (exposes latent webhook/IAM
  bugs) → judge by **pod readiness**.
- **Descheduler** (`descheduler`, [ADR-093](../../adrs/093-descheduler-node-rebalancing.md)): CronJob,
  **`LowNodeUtilization`** — evicts off over-full nodes to repack (respects PDBs, `nodeFit: true`, skips
  DaemonSet/system). Per-cluster: platform 40/70% `*/15`; **preprod 50/70% `*/10`** (raised because a 39% node
  sat one point under the 40% default). Fixes the post-unpark 59/14-pod meltdown.
- **`cost_profile`** (`_base.hcl`): `dev` → `high_availability=false`, single-AZ, LGTM+P **off**
  (Prometheus-only); `prod` → RF3 + full stack. **`high_availability`** drives RF1 vs RF3 + Loki
  SingleBinary vs SimpleScalable.
- **No S3 storage-class tiering** — the store buckets' lifecycle rules are **version-hygiene** (noncurrent
  expiry + abort-multipart), not Glacier/IA tiering; retention is the compactor's job.
- **Savings Plans / RIs: deferred** — no budget **and** direct tension with parking (committing to compute you
  park = paying for it turned off). If ever budgeted: commit only to the **24/7 floor**, 1yr no-upfront.

## Operate — guardrails & practice ([deep dive](deep-dive-operate-guardrails-and-the-practice.md))

- **Per-team guardrail** ([ADR-091](../../adrs/091-cost-guardrails.md), **surface → alert → enforce**):
  - **Envelope:** `Team.spec.envelope.budget.monthlyUSD` in `gitops/teams/*.yaml` → KSM metric
    `team_budget_monthly_usd` (single source).
  - **Surface** (live): per-team budget-utilization % panel. **Alert** (live): Mimir-ruler burn-rate rule in
    the **spoke tenant** → 80% warning / 100% critical → owner-routing.
  - **Enforce** (live **preprod**, `Audit`): hourly `cost-budget-enforcer` CronJob computes spend÷budget →
    writes `cost-budget-status` ConfigMap → Kyverno `restrict-over-budget-provisioning` **denies XEnvironment
    CREATE** for `exceeded` teams (unless `cost.refplat.org/budget-override: "true"`). **Two fail-open layers**
    (CronJob `curl … || exit 0`; Kyverno `failurePolicy: Ignore`). **Never touches running workloads.** On
    preprod only — env-API `Team`/`XEnvironment` CRDs live there, not the hub (ADR-048).
- **AWS Budgets + Cost Anomaly Detection** (#1054, **mgmt/payer acct**, module `aws/cost-monitoring`): 2
  Budgets tripwires (80% actual / 100% actual / 100% forecast) + 1 **dimensional SERVICE** anomaly monitor
  (IMMEDIATE SNS) → SNS topic → Chatbot(Slack) + email. Gotchas: **only ONE dimensional monitor per account**
  → subscribe to the auto-created `Default-Services-Monitor`, don't create a 2nd; **topic unencrypted by
  design** (managed KMS key can't grant `budgets`/`costalerts` principals + Chatbot can't read a CMK topic).
- **Infracost shift-left** (#1056, `.github/workflows/infracost.yml`): prices a Terraform change **in the PR**.
  Prices the shared **modules**, *not* live units (the Terragrunt evaluator can't parse `env.hcl`+SOPS).
- **Cost-allocation tags** (#673): `Team`+`Environment` CUR tags — forward-only, ~24h activation, no backfill.

## Status ledger (verified live)

- **LIVE + exercised:** OpenCost (both clusters), true-cost/CUR odometer (hub, #668), per-team dashboards +
  budget-utilization, burn-rate alerts, **budget-enforcer** (preprod, audit-first, deny *proven*), Karpenter
  consolidation (both), cluster parking (repeatable), descheduler (both), cost-allocation tags, Infracost
  shift-left, AWS Budgets + Anomaly (built; **email pending-confirm**, **Slack gated-off** #1063).
- **Designed / not built:** Backstage cost tab (ADR-091 A3); AWS **Compute Optimizer** (#1055); **kube-green**
  off-hours (#1057); **Cloud Custodian** janitor (#1058); platform-shared cost bucket (#1053); FinOps
  cadence/forecasting (#1059); FinOps XAgent (D7).
- **Deferred (budget) / rejected (principle):** **Savings Plans/RIs** + Infracost Cloud (deferred on budget);
  vended FinOps SaaS — CloudHealth/Cloudability/Vantage (rejected, second control plane).
- **Doc-drift:** ADR-091 + ADR-092 still call **#668 "unbuilt"** — stale (it's built + closed).

## Tool verdicts (ADR-092)

| Verdict | Tools |
| --- | --- |
| **Reaffirm** | OpenCost |
| **Adopt** (free/native) | Infracost (self-hosted CLI) · AWS Budgets · Cost Anomaly Detection · Compute Optimizer · Cost Allocation Tags · CUR→Athena |
| **Trial** | kube-green (per-ns off-hours) · Cloud Custodian (account janitor) |
| **Hold** | Kubecost OSS · Komiser · OptScale |
| **Reject** | Vended FinOps SaaS (CloudHealth/Cloudability/Vantage) — second control plane |

## Gotchas

- **One number is a lie** — OpenCost = list-price estimate, CUR = discounted actual; trend vs verdict.
- **`max` not `sum`** on the monthly true-cost gauge (#668).
- **CUR lags ~24h** (first delivery ~24h after create) — check the "data freshness (age)" panel.
- **Cost control ≠ availability control** — the enforcer is fail-open + gates *only new provisioning*.
- **Verify a park via the EKS API, not kubectl** (parking kills the Tailscale router).
- **Savings Plans fight parking** — commit only to the un-parkable 24/7 floor.

## Go deeper

Deep dives: [Inform](deep-dive-inform-the-two-meters.md) · [Optimize](deep-dive-optimize-the-cost-levers.md) ·
[Operate](deep-dive-operate-guardrails-and-the-practice.md). Runbooks: `docs/runbooks/cost-{true-spend,
alerting,shift-left}.md`. Related: [Observability](../observability/orientation.md),
[Foundations](../foundations/orientation.md). External:
[FinOps Framework](https://www.finops.org/framework/) · [OpenCost](https://www.opencost.io/docs/) ·
[Karpenter](https://karpenter.sh/docs/) · [Infracost](https://www.infracost.io/docs/).
