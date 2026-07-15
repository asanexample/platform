# Learn: Cost & FinOps — orientation

How the platform turns cloud spend from a bill that *arrives* into a signal you *engineer* — who spent it,
whether it was worth it, and how to keep it down — without a finance team, and without buying a
cost-management SaaS.

Cost here is just another signal in the same LGTM+P stack as [Observability](../observability/orientation.md),
and a lot of a small platform's bill comes from the always-on pieces [Foundations](../foundations/orientation.md)
covers — EKS control planes, NAT gateways. If you know roughly that AWS charges you for compute and data, you
know enough to start.

## The question

Someone asks: *"What did the platform cost last month, which team spent it, and was any of it waste?"* On most
teams that goes to a spreadsheet a finance person assembles days later from a PDF invoice. Here it's a
dashboard, attributed per team, reconciled against the actual AWS bill, with automatic guardrails — and none
of it is rented from a vendor. It's built into the platform's own fabric.

One caveat up front, because stating it is part of the teaching: this platform is *small* in absolute dollars —
a couple of EKS clusters, a few baseline nodes, three NAT gateways, no big databases. It won't save anyone a
fortune. The point is to demonstrate a correct, scalable FinOps practice — the machinery a real org needs —
not to chase a big number. A reference platform earns trust by doing the right thing at small scale so it's
ready at large scale.

## The one idea: cost is an engineering signal, on a loop

FinOps makes cloud cost a first-class engineering signal — visible, attributed to a team, optimizable, and
governed — run as a continuous loop: **Inform** (see it honestly), **Optimize** (act to reduce it),
**Operate** (govern it with budgets and a practice). Each phase is built into the platform's own stack rather
than bought as a cost SaaS.

That loop isn't ours. It's the [FinOps Foundation Framework](https://www.finops.org/framework/), the
industry-standard operating model, which the platform adopts wholesale. It's the spine of this whole doc.

Think of metering and managing the utilities for a shared building. The cloud bill is the building's
power-and-water bill. **Inform** is the metering — a sub-meter per tenant so each team sees its own draw, plus
the actual utility invoice to reconcile against. **Optimize** is efficiency — lights off in empty rooms
overnight (parking), HVAC right-sized to occupancy (Karpenter). **Operate** is the house rules — a breaker
that trips before a tenant blows the budget, a smoke alarm for a sudden spike, and an agreed practice for
reviewing it all. Where the metaphor breaks: a landlord *bills* tenants to recover cost; here nobody pays
anybody. The "bill" is a signal to engineer against, and the largest slice — the shared plant — is
deliberately charged to no one. More on that below.

The tour follows the loop: Inform, then Optimize, then Operate.

---

## Inform — see it honestly (two meters)

You can't manage what you can't see, and the subtle part is that one cost number is a lie. The platform runs
*two* meters, and the whole Inform layer rests on knowing which answers which question
([deep dive](deep-dive-inform-the-two-meters.md)).

- **The speedometer — [OpenCost](https://www.opencost.io/).** An in-cluster meter that multiplies each pod's
  live CPU/memory/storage usage by the node's public list price, rolled up per team (by the environment
  namespace's `team` label). It's fast — it updates continuously and tells you your current *rate* of spend,
  so a team whose burn just doubled shows up now. But it's an estimate at list price: it knows nothing about
  discounts, and it can't see cost that isn't a running pod (NAT gateways, the control plane, data transfer).
- **The odometer — the real AWS bill.** A small exporter queries the Cost & Usage Report (the actual invoice
  data) via Athena and re-serves it as metrics. This is the authoritative total — it *does* see discounts,
  Savings Plans, and the non-pod costs OpenCost is blind to — but it lags ~24 hours, so it's a verdict, not a
  live gauge.

The house rule: trend on the speedometer, verdict on the odometer. A dashboard panel places the two side by
side for reconciliation. One gotcha lives here: the odometer metric is a *monthly gauge* — the exporter
re-emits the same running total every scrape — so you aggregate it with `max`, never `sum`, or you count the
same dollars many times over.

**Shared cost that belongs to no team.** A big share of a small platform's bill can't be attributed to a
tenant: the EKS control planes, the NAT gateways (a real big-ticket item), the Transit Gateway, the whole
observability stack and its S3, ArgoCD, Crossplane. FinOps calls this the platform-shared scope, and the rule
is to surface it plainly and never silently
socialize it onto team budgets — doing so would corrupt the very per-team signal you're trying to build.
Allocate what's allocatable; show the rest honestly.

---

## Optimize — act to reduce it (the levers)

Seeing cost is worthless if nothing acts on it. Three levers are built and live, each continuously reducing
spend ([deep dive](deep-dive-optimize-the-cost-levers.md)).

- **[Karpenter](https://karpenter.sh/) — right-sizing + consolidation**, the biggest continuous lever.
  Instead of fixed-size node groups, Karpenter
  provisions just-in-time nodes sized to the actual pending pods, and — the cost part — consolidation
  continuously bin-packs workloads and terminates underutilized nodes. It's a valet who re-parks the whole lot
  continuously, picks the right-sized space for each car, and closes empty aisles — versus the old autoscaler
  that could only use pre-marked, fixed-size spaces. What *lets* it consolidate is upstream: every new service
  ships a default HPA that scales its pods down as load falls — fewer pods free up node
  capacity, which is exactly what Karpenter then reclaims. The HPA right-sizes the pods, Karpenter right-sizes
  the nodes.
- **Cluster parking — lights off overnight**, the biggest non-prod lever. `platctl down` scales the node
  groups to zero overnight, dropping nearly all compute cost, and it's non-destructive: the control plane and
  every database volume are preserved, so `up` brings everything back. Proven boringly repeatable.
- **The descheduler — re-seat the guests.** The
  scheduler places a pod once and never moves it; on a cluster that parks, unparks, and consolidates, that
  leaves nodes lopsided. A periodic job evicts pods off over-full nodes so they repack onto emptier ones,
  respecting disruption budgets — the host who re-seats guests so one table isn't crammed while another sits
  empty. It packs onto fewer nodes and prevents a real post-unpark meltdown.

Under those, one toggle does a lot of quiet work: `cost_profile`. Flip an environment to `dev` and it fans out
to a cheaper shape — single-replica stores at replication-factor 1, single-AZ nodes, the durable LGTM+P stores
off (Prometheus-only). Flip it to `prod` and you get the full RF3, multi-AZ production shape. The same
platform, sized by one boolean.

**The lever the platform deliberately does *not* pull — Savings Plans.** Committing to a year of discounted
compute is the biggest steady-state lever a real company has. It's deferred here for two independent reasons: there's no spend budget to commit, and — the
teaching point — it's in direct tension with parking. Savings Plans are a gym membership: cheaper per visit
only if you actually go every day. Parking the cluster is skipping the gym twelve hours a day — you don't buy
an annual pass for a gym you lock overnight. The resolution, if ever budgeted: commit only to the genuine 24/7
floor — the always-on system pieces that never park — never the elastic part.

---

## Operate — govern it (guardrails + a practice)

The last phase turns cost from something you watch into something with rules — a per-team guardrail, two
bill-level tripwires, and an operating model ([deep dive](deep-dive-operate-guardrails-and-the-practice.md)).

**The tenant guardrail — a per-team budget with a soft brake**,
built in the same surface → alert → enforce pattern as [Policy](../policy/orientation.md)'s Audit→Enforce.
Each team carries a budget envelope in the git registry (`Team.spec.envelope.budget.monthlyUSD`) — the breaker
rating stamped on the panel, declared once, read by every meter. From it:

- **Surface:** a per-team "budget utilization %" panel (spend ÷ budget).
- **Alert:** a burn-rate rule pages the owning team at 80% (warning) and 100% (critical), routed to *their*
  channel via the [triage agent's](../identity/orientation.md) owner-routing.
- **Enforce:** an hourly job writes each over-budget team into a ConfigMap that a Kyverno policy reads to block
  that team from provisioning new environments — until they're back under budget or an admin grants an
  override. It's audit-first and fail-open (a broken query or a down policy engine never blocks), and it only
  gates new provisioning — it never touches running workloads. A cost control must never become an
  availability control.

**The platform tripwires — AWS Budgets + Cost Anomaly Detection** (in the payer account). Distinct from
the per-team path: these watch the whole bill. AWS Budgets is the tripwire on the fence — alert at 80%/100% of
a monthly threshold. Cost Anomaly Detection is the smoke detector — trip on an unexpected spike regardless of
threshold, the canonical catch being a control-plane-logging surprise. Both fan out to a dedicated Slack/email
channel owned by the platform team.

**The practice.** Above the mechanisms sits the
operating model: adopt the FinOps Framework, track maturity Crawl→Walk→Run, and — a firm principle — use free
OSS + AWS-native tools only, and never a vended cost SaaS. A second cost control plane would contradict the
whole build-it-in-our-own-fabric demonstration. So: OpenCost, AWS Budgets/Anomaly, and
[Infracost](https://www.infracost.io/) shift-left — a CI check that prices a Terraform change in the pull
request — are adopted; Kubecost, Cloudability, and friends are held or rejected.

---

## The honest status — what's built vs. named

The core loop is genuinely live. Both meters (OpenCost + the CUR odometer), all three optimize levers
(Karpenter, parking, descheduler), the full per-team guardrail (surface/alert/enforce — enforce live on
preprod, audit-first), the AWS tripwires, cost-allocation tags, and Infracost shift-left are built and
running.

What's named but not built, and the docs say so: AWS Compute Optimizer, kube-green (per-namespace off-hours
scaling), and Cloud Custodian (an account janitor) are adopted in the framework but unbuilt; Savings Plans are
documented-but-unbought (above); and the AWS alert Slack delivery is wired but gated off pending a one-time
manual workspace authorization (email works). The FinOps practice is deliberately mid-flight — Crawl→Walk,
honestly.

## When it breaks — the ones you'll actually hit

- **"OpenCost and the bill disagree."** They should — OpenCost is a list-price estimate, the CUR is the
  discounted actual. Trend on one, verdict on the other; the reconciliation panel shows the gap.
- **"The true-cost dashboard is empty / stale."** The CUR lags ~24h, and a freshly created report takes ~24h
  for its first delivery. The "data freshness (age)" panel tells you if it's stale vs just lagging.
- **"My true-cost number looks huge / doubled."** You aggregated the monthly gauge with `sum`. Use `max`
  — the exporter re-emits the same total each scrape.
- **"A team can't create an environment."** Check its budget status — the enforcer may have marked it
  `exceeded`. That's the guardrail working; an admin override annotation is the escape hatch.
- **"I parked the cluster and kubectl hangs."** Scaling to zero also drops the in-cluster Tailscale router —
  verify a park via the AWS EKS API, not kubectl (see the
  [Optimize deep dive](deep-dive-optimize-the-cost-levers.md)).

## Go deeper

- [Inform — the two meters](deep-dive-inform-the-two-meters.md) — OpenCost vs the CUR/Athena pipeline,
  per-team attribution, shared cost, the max-not-sum gotcha.
- [Optimize — the cost levers](deep-dive-optimize-the-cost-levers.md) — Karpenter consolidation, cluster
  parking, the descheduler, `cost_profile`, and the Savings-Plans-vs-parking tension.
- [Operate — guardrails & the practice](deep-dive-operate-guardrails-and-the-practice.md) — the per-team
  budget enforcer, AWS Budgets + Anomaly Detection, and the FinOps operating model + tool verdicts.
- The lookup: the [Reference](reference.md). Related: [Observability](../observability/orientation.md) (cost
  is a signal in the same stack), [Foundations](../foundations/orientation.md) (the always-on cost drivers).
