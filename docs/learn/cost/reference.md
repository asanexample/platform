# Learn: Cost & FinOps — reference

A lookup of how cost and FinOps work on this platform, verified against code and the live clusters. Dollar
figures, account IDs, and the personal alert address are left out on purpose — this is the mechanism, not the
bill. The [orientation](orientation.md) builds the model behind it.

## The loop (FinOps Foundation Framework)

**Inform → Optimize → Operate**, run iteratively; maturity tracked Crawl→Walk→Run. **Scopes:**
`platform-shared` (control planes, NAT/TGW, observability + its S3, ArgoCD/Crossplane — surfaced, never
socialized), `per-team/tenant`, and `AI/GenAI` (emerging, not built). Principle: **free OSS +
AWS-native only; no vended cost SaaS, ever.**

## Inform — the two meters ([deep dive](deep-dive-inform-the-two-meters.md))

| | **OpenCost** (speedometer) | **true-cost-exporter** (odometer) |
| --- | --- | --- |
| Measures | in-cluster **allocation estimate** (usage × **list price**) | **actual AWS bill** (CUR — sees discounts/SP/RI + non-pod cost) |
| Freshness | near-real-time (current *rate*) | **lags ~24h** (monthly *verdict*) |
| Attribution | `platform.refplat.org/team` namespace label | activated **`Team` CUR cost-allocation tag** |
| Blind to | discounts, NAT/control-plane/data-transfer/EBS/S3 | live rate (only a daily total) |
| Module | `observability-opencost/main.tf` (both clusters) | `observability-opencost/true-cost-exporter.tf` (hub) |

House rule: **trend on OpenCost, verdict on the CUR.** The `platform-cost.json` dashboard shows both + an
estimate-vs-actual reconciliation panel.

- **Max-not-sum:** true-cost is a **monthly gauge** re-emitted every scrape → `sum()` double-counts;
  aggregate with **`max`** (`max(platform_true_cost_monthly_usd_total)`).
- **The CUR pipeline** (module `aws/cost-export`, **mgmt/payer account**, us-east-1): legacy CUR (not CUR 2.0 —
  OpenCost cloudCost expects legacy schema) → S3 (**AES256** not KMS — billingreports can't use the managed
  key) → Glue db + daily crawler → Athena workgroup → cross-account **`cost_reader`** role. The hub exporter
  assumes it via **Pod Identity** — needs `sts:AssumeRole` **+ `sts:TagSession`** (session tags don't
  propagate through a further AssumeRole without it). First CUR delivery ~24h after create.
- **Shared/unallocable cost:** EKS control planes, **NAT gateways** (big-ticket), TGW, LGTM+P +
  its S3, ArgoCD/Crossplane → rolled up to a `platform` bucket (`label_replace(..., "team","platform","team","^$")`),
  never split into fake per-team cost.

## Optimize — the levers ([deep dive](deep-dive-optimize-the-cost-levers.md))

- **Karpenter** (`aws/karpenter`): JIT nodes sized
  to pending pods, plus consolidation (bin-pack + terminate underutilized). The two clusters differ: hub is
  on-demand-only + `WhenEmpty` (its stateful singletons would be disrupted by a spot reclaim); preprod runs
  `["spot","on-demand"]` + `WhenEmptyOrUnderutilized` — the spot capacity-type is live on preprod. Gotchas: a min 8 GiB node floor (`min_instance_memory_mib
  = 6144`; the DaemonSet slab is ~3.2 GiB); an SCP exemption is mandatory (`<cluster>-eks-karpenter-*`, anchored
  per-cluster, not a leading-wildcard, in `exempt_roles`) or DenyTeamTagTampering/require-tagging 403s every
  launch; and the BYOCNI `node.cilium.io/agent-not-ready` startup taint.
- **Cluster parking** (`platctl down/up`, `cluster-parking` skill): node groups → **`desiredSize=0`** overnight;
  **non-destructive** (control plane + EBS/CNPG preserved); reversible. Judge a park via the **EKS API, not
  kubectl** (parking drops the Tailscale router); unpark = fresh pod admission (exposes latent webhook/IAM
  bugs) → judge by **pod readiness**.
- **Descheduler** (`descheduler`): CronJob,
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

- **Per-team guardrail** (**surface → alert → enforce**):
  - **Envelope:** `Team.spec.envelope.budget.monthlyUSD` in `gitops/teams/*.yaml` → KSM metric
    `team_budget_monthly_usd` (single source).
  - **Surface** (live): per-team budget-utilization % panel. **Alert** (live): Mimir-ruler burn-rate rule in
    the **spoke tenant** → 80% warning / 100% critical → owner-routing.
  - **Enforce** (live on **preprod**, `Audit`): an hourly `cost-budget-enforcer` CronJob computes spend÷budget,
    writes a `cost-budget-status` ConfigMap, and Kyverno `restrict-over-budget-provisioning` then denies
    XEnvironment CREATE for `exceeded` teams (unless `cost.refplat.org/budget-override: "true"`). Two fail-open
    layers guard it (CronJob `curl … || exit 0`; Kyverno `failurePolicy: Ignore`), and it never touches running
    workloads. Preprod only — the env-API `Team`/`XEnvironment` CRDs live there, not on the hub.
- **AWS Budgets + Cost Anomaly Detection** (**mgmt/payer acct**, module `aws/cost-monitoring`): 2
  Budgets tripwires (80% actual / 100% actual / 100% forecast) + 1 dimensional SERVICE anomaly monitor
  (IMMEDIATE SNS) → SNS topic → Chatbot(Slack) + email. Gotchas: there's only one dimensional monitor per
  account, so subscribe to the auto-created `Default-Services-Monitor` rather than making a second; and the
  topic is unencrypted by design (the managed KMS key can't grant `budgets`/`costalerts` principals, and
  Chatbot can't read a CMK topic).
- **Infracost shift-left** (`.github/workflows/infracost.yml`): prices a Terraform change **in the PR**.
  Prices the shared **modules**, *not* live units (the Terragrunt evaluator can't parse `env.hcl`+SOPS).
- **Cost-allocation tags:** `Team`+`Environment` CUR tags — forward-only, ~24h activation, no backfill.

## Status ledger (verified live)

- **LIVE + exercised:** OpenCost (both clusters), true-cost/CUR odometer (hub), per-team dashboards +
  budget-utilization, burn-rate alerts, **budget-enforcer** (preprod, audit-first, deny *proven*), Karpenter
  consolidation (both), cluster parking (repeatable), descheduler (both), cost-allocation tags, Infracost
  shift-left, the **Backstage cost tab**, AWS Budgets + Anomaly (built; **email pending-confirm**, **Slack gated-off**).
- **Designed / not built:** AWS **Compute Optimizer**; **kube-green**
  off-hours; **Cloud Custodian** janitor; platform-shared cost bucket; FinOps
  cadence/forecasting; FinOps XAgent.
- **Deferred (budget) / rejected (principle):** **Savings Plans/RIs** + Infracost Cloud (deferred on budget);
  vended FinOps SaaS — CloudHealth/Cloudability/Vantage (rejected, second control plane).

## Tool verdicts

| Verdict | Tools |
| --- | --- |
| **Reaffirm** | OpenCost |
| **Adopt** (free/native) | Infracost (self-hosted CLI) · AWS Budgets · Cost Anomaly Detection · Compute Optimizer · Cost Allocation Tags · CUR→Athena |
| **Trial** | kube-green (per-ns off-hours) · Cloud Custodian (account janitor) |
| **Hold** | Kubecost OSS · Komiser · OptScale |
| **Reject** | Vended FinOps SaaS (CloudHealth/Cloudability/Vantage) — second control plane |

## Gotchas

- **One number is a lie** — OpenCost = list-price estimate, CUR = discounted actual; trend vs verdict.
- **`max` not `sum`** on the monthly true-cost gauge.
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
