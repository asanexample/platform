# ADR-092: Platform FinOps Practice — adopting the FinOps Framework for the platform's own spend

**Date:** 2026-06-30

**Status:** Proposed

## Context

[ADR-091](091-cost-guardrails.md) made **tenant** cost a governed dimension — per-team budgets on the
Team envelope, burn-rate alerts, and audit-first enforcement on provisioning. That covers the *teams running
on* the platform. It does **not** cover two things a credible internal developer platform also needs:

1. **The platform's *own* cost** — the shared infrastructure no single team is billed for: the two EKS control
   planes, the NAT gateways (a known big-ticket item), the Transit Gateway, the LGTM+P observability stack and
   its S3 stores, ArgoCD, Crossplane, the Keycloak/Backstage/agent control planes, and the hub itself. ADR-091
   explicitly flagged this as the **"unattributable shared cost"** that must be surfaced honestly and never
   silently socialized onto teams — but it left the *how* unspecified.
2. **A FinOps *practice*** — an operating model, not just dashboards. Today cost work is real but ad-hoc:
   OpenCost allocation (live), the ADR-091 guardrails (live), Karpenter consolidation ([ADR-078](078-cluster-elasticity-karpenter.md)),
   the nightly hand-park, cost-allocation tags (#673, scoped), the CloudWatch `$356/mo` control-plane-logging
   fire-drill (PR #466). These are capabilities without a *framework* tying them together, naming the gaps, and
   giving them a cadence. The CloudWatch surprise is the cautionary tale: visibility without an operating model
   means you find the leak on the bill, not before.

**The industry has a standard for this — the [FinOps Foundation Framework](https://www.finops.org/framework/)**,
and adopting it (rather than inventing our own vocabulary) is both the right engineering call and on-mission:
this is a **reference platform**, so demonstrating a textbook FinOps practice *is* a deliverable. The framework
(2025 revision) has four parts we adopt verbatim as our operating model:

- **Principles** — teams collaborate; business value drives technology decisions; everyone owns their usage;
  FinOps data is accessible, timely, and accurate; FinOps is enabled centrally; take advantage of the cloud's
  variable cost model.
- **Phases** — **Inform → Optimize → Operate**, run iteratively (visibility → act on savings → govern/automate).
- **Domains & Capabilities** — Understand Usage & Cost, Quantify Business Value, Optimize Usage & Cost, Manage
  FinOps Operations; 22 capabilities including cost allocation, data ingestion/normalization, forecasting &
  budgeting, **anomaly management**, **rate optimization** (commitments/discounts), **workload optimization**
  (rightsizing/idle), reporting & analytics, and establishing a FinOps culture.
- **Scopes** (the 2025 addition) — a *Scope* is a segment of technology spend aligned to a business construct.
  We adopt two now — **platform-shared** and **per-team/tenant** (ADR-091) — and name **AI/GenAI** as the
  emerging third (agent inference spend, [ADR-076](076-agent-observability.md)/[ADR-082](082-platform-agent-runtime-xagent.md)).

A footprint reality check ([ADR-079](079-cloud-resource-monitoring-scope.md)): the platform is **small in
absolute dollars** — 2 EKS clusters, ~3 baseline nodes, 3 NAT gateways, 1 TGW, 0 RDS, 0 ALB, S3 for state +
observability. The point of this ADR is therefore **not** chasing large savings; it is to **demonstrate a
correct, scalable FinOps practice** ([design-for-scale](../../ROADMAP.md)) and to keep the platform honest
about its own cost — the same way we dogfood every other capability.

A second hard constraint: this reference platform runs on **no spend budget** of its own, so the in-scope-now
toolset is strictly **free** — OSS we already operate plus the free-tier native services. Anything that costs
money — commitment purchases (**Savings Plans / RIs**) or paid SaaS tiers — is **designed in but deferred** to a
future budgeted state, so a real company standing this up has a ready path without us pretending we can spend
today. (The one exception is *principle*, not budget: a vended FinOps control plane stays out regardless — see
the Decision.)

This ADR decides the **practice and the platform-shared Scope**. It does not redo ADR-091 (tenant Scope) or
ADR-079 (the monitoring backbone); it sits above both and folds them in as the parts they are.

## Decision

**D1 — Adopt the FinOps Framework as the platform's cost operating model.** All cost work — existing and new —
is organized under the **Inform → Optimize → Operate** phases and mapped to framework Capabilities. We track our
maturity per capability (Crawl → Walk → Run) rather than treating cost as a one-off project. This is the
*decide-once* coherence move ADR-090 made for roles and ADR-091 made for budgets, applied to the whole cost
domain.

**D2 — The platform-shared cost bucket is a first-class Scope, surfaced honestly.** Cost that is genuinely
un-attributable to a team (control planes, NAT/TGW, observability + its S3, ArgoCD/Crossplane/Keycloak/Backstage,
the hub) is reported as an explicit **`platform-shared`** line in Grafana and Backstage — *allocate what is
allocatable, show the rest plainly*. It is never silently spread across tenant budgets (that would corrupt the
ADR-091 signal). The shared bucket gets the same Inform/Optimize/Operate treatment as a tenant.

**D3 — Inform (visibility & allocation): complete the authoritative bill.** The split decided in ADR-091 D2
holds — **OpenCost = the speedometer** (fast in-cluster allocation, live), **CUR → Athena = the odometer** (the
true bill with discount/commitment awareness; issue #668, the unbuilt half). Apply the **cost-allocation tags**
(`Team` + `Environment`, #673 — forward-only with a ~24h activation lag, so apply early) as the join key.
Converge on **one pane**: the existing Grafana cost dashboards + the Backstage Cost tab, extended with a
`platform-shared` view. No parallel cost system (ADR-091 D5).

**D4 — Optimize (act on savings):**

- **Workload optimization** — rightsizing via **AWS Compute Optimizer** recommendations + requests/limits
  discipline; Karpenter consolidation (ADR-078, live) is the node-level lever.
- **Idle elimination** — systematize the nightly whole-cluster park (ADR-091 D4) and add **per-namespace
  off-hours scale-to-zero** for the daytime-idle case the whole-cluster park can't reach.
- **Rate optimization** — **deferred today** (D6): commitment purchases (Savings Plans / RIs) cost real money
  up front, and this reference platform runs on no spend budget. We **document the practice now** — what we
  *would* commit (the genuine 24/7 floor only), how (Cost Explorer SP recommendations, 1-year no-upfront first),
  and the elasticity caveat (see risks) — so the path is ready the moment there's a budget, but we **do not buy**.
- **Data-transfer / NAT** — treat NAT-gateway and cross-AZ/cross-VPC data transfer as a named optimization
  target (VPC endpoints for S3/ECR/etc. to bypass NAT; the TGW path already exists).

**D5 — Operate (govern & automate):**

- **Budgets & anomaly detection** — stand up **AWS Budgets** (per-account + a platform-shared budget) and
  **AWS Cost Anomaly Detection** (ML, the clear current gap), delivered to the **platform team** in Slack +
  email. *(Build correction, #1054: these are payer-account services whose owner is the platform team, so they
  deliver via a dedicated SNS topic → AWS Chatbot → Slack — **not** the in-cluster, tenant-scoped owner-routing
  fabric of ADR-084. Owner-routing resolves which **tenant** team owns a problem; **tenant** budget alerts
  already ride ADR-091's Mimir-ruler → owner-routing. See `docs/runbooks/cost-alerting.md`.)*
- **Shift-left cost** — surface the cost delta of an infrastructure change **in the PR**, on the Terragrunt /
  OpenTofu repo, before apply (tooling in D6). This is the "everyone owns their usage" principle made real for
  *platform* engineers, mirroring ADR-091's shift-left for tenants.
- **Forecasting & cadence** — month-end forecast vs budget, and a lightweight **recurring FinOps review**
  (a documented cadence, owner = Platform Lead) — the "Manage FinOps Operations" domain.
- **Tenant Operate** = ADR-091 (the per-team guardrails are the tenant slice of this phase, unchanged).

**D6 — Free and open-source / AWS-native only today; paid services and commitments are deferred, not designed
out.** This reference platform runs on **no spend budget**, so the in-scope-now set is strictly *free* — OSS we
already run, plus the free-tier native services (Budgets, Cost Anomaly Detection, Compute Optimizer). Anything
that costs money — **Savings Plans / RIs** (commitment spend), paid SaaS tiers (Infracost Cloud), or a vended
FinOps platform — is **deferred to a future budgeted state** and documented (§ *Deferred to a future budgeted
state*) so the path is ready, not taken. Note the two *kinds* of "no": commitment purchases and paid tiers are
deferred on **budget** (a real company with a real bill should adopt Savings Plans — it's the single biggest
steady-state lever); a **vended FinOps control plane** stays out on **principle** (modeling cost in our own
fabric *is* the demonstration — a second control plane contradicts it, budget or not). Specific tool decisions
are in **§ Tooling recommendations** below.

**D7 — A FinOps agent is the future Operate automation, deferred.** An autonomous spend-watcher fits the
`XAgent` runtime (ADR-082) and is the natural consumer of this practice *once* the budgets, anomaly signal, and
shared-cost surfacing exist for it to act on (consistent with ADR-091's deferral). When that work starts,
**re-evaluate the [AWS FinOps agent](https://aws.amazon.com/blogs/aws-cloud-financial-management/aws-finops-agent-is-now-public-preview/)**
(public preview) as both a candidate and a concrete third-party-agent onboarding test for the agentic-workloads
substrate (ADR-074). Not built by this ADR.

### Capability map (where we are today)

| FinOps capability | Today | Phase | This ADR adds |
|---|---|---|---|
| Cost allocation (in-cluster) | OpenCost, live both clusters (ADR-091) | Inform | `platform-shared` view (D2) |
| Data ingestion / true bill | CUR→Athena scoped, **unbuilt** (#668) | Inform | Build it (D3) |
| Cost-allocation tagging | Module scoped, **not applied** (#673) | Inform | Apply it (D3) |
| Reporting & analytics | Grafana dashboards + Backstage Cost tab, live | Inform | Shared-cost pane (D2) |
| Budgeting | Per-team budgets, live (ADR-091) | Operate | Account + platform budgets (D5) |
| **Anomaly management** | **none** | Operate | AWS Cost Anomaly Detection (D5) |
| Forecasting | none | Operate | Forecast vs budget + cadence (D5) |
| Workload optimization | Karpenter consolidation (ADR-078); manual rightsizing | Optimize | Compute Optimizer; off-hours scale-to-zero (D4) |
| **Rate optimization** | **none** (Savings Plans untouched; spot retired ADR-078) | Optimize | *Documented, deferred* — no commitment budget now (D4/D6) |
| Idle elimination | Nightly whole-cluster park (manual) | Optimize | Systematize + per-ns off-hours (D4) |
| Shift-left / unit economics | none for platform IaC | Operate | Cost-in-PR (D5/D6) |
| FinOps culture / cadence | ad-hoc | Operate | Documented review cadence (D5) |

## Tooling recommendations

Evaluated against our actual stack (OpenTofu + Terragrunt, EKS + Cilium, OpenCost + Grafana/Mimir, Kyverno,
Backstage, the ADR-084 owner-routing). Verdicts: **Reaffirm** (keep), **Adopt** (build in), **Trial**
(spike, low commitment), **Hold** (not now), **Reject**.

| Tool | Verdict | Rationale |
|---|---|---|
| **OpenCost** | Reaffirm | In-cluster allocation, already live both clusters; the Inform speedometer. |
| **CUR → Athena + OpenCost `cloudCost`** | Adopt | The authoritative bill (#668); OpenCost `cloudCost` reuses Mimir + our dashboards — no Grafana Athena plugin needed (ADR-079). |
| **AWS Cost Allocation Tags** | Adopt | The CUR join key (#673); apply early (~24h forward-only lag). IaC'd already, just needs applying. |
| **AWS Budgets** | Adopt | Account + `platform-shared` budgets; native, IaC via the AWS provider; alerts → SNS → Chatbot/Slack + email (platform team). |
| **AWS Cost Anomaly Detection** | Adopt | ML anomaly detection, **free**, fills the biggest capability gap; SNS → the ADR-084 fabric. Begins working within ~24h. |
| **AWS Compute Optimizer** | Adopt | Free rightsizing recommendations (EC2/ASG/EBS); feeds workload optimization. |
| **Savings Plans (Compute SP)** | **Defer** (no budget) | The biggest steady-state lever in a *real* company — but commitments cost real money up front and we have no spend budget. **Document, don't buy**: sized to the 24/7 floor only, Cost Explorer SP recommendations, 1-year no-upfront first. Adopt when budgeted. |
| **Infracost** | **Adopt** | Best-fit shift-left: scans **Terragrunt/OpenTofu** and posts a **cost diff in the PR** before apply. CLI is open-source + free (free pricing-API key); **self-host the CI step, skip the paid Infracost Cloud**. Slots straight into our existing PR-gate model — the platform-engineer analogue of ADR-091's tenant shift-left. |
| **kube-green** | Trial | CRD-based (`SleepInfo`) per-namespace off-hours scale-to-zero; CNCF sandbox. Covers the **daytime per-environment idle** the whole-cluster park can't, and composes with Karpenter (pods→0 lets Karpenter reclaim nodes). Low-commitment spike for D4. |
| **Cloud Custodian (c7n)** | Trial | Policy-as-code janitor for **AWS-account-level** waste Kyverno can't see — orphaned EBS (#242), untagged resources, idle/forgotten infra, off-hours rules. Complements (doesn't overlap) Kyverno, which is in-cluster only. Evaluate vs. doing the same in Terragrunt/Lambda. |
| **Kubecost (OSS)** | Hold | Adds a UI layer over OpenCost we don't need (we have Grafana + Backstage); the differentiating features are paid. OpenCost already gives us the allocation engine. |
| **Komiser / OptScale / OpenInfraQuote** | Hold | Inventory/dashboard/estimation niches we already cover with Grafana + OpenCost + (adopted) Infracost. Revisit only if a concrete gap appears. |
| **Vended FinOps SaaS** (CloudHealth, Cloudability, Vantage) | Reject | A second cost control plane contradicts the build-it-in-our-fabric demonstration (ADR-091 alternatives). |

**Net new tools to bring in (all free): Infracost (adopt), AWS Budgets / Cost Anomaly Detection / Compute
Optimizer (adopt — native, free), and a kube-green + Cloud Custodian trial.** Everything else is reaffirm,
hold, or deferred-on-budget below.

### Deferred to a future budgeted state

Documented now so the path is ready the day there's a budget — none of these are adopted today (D6):

- **Savings Plans / Reserved Instances** — the highest-leverage rate optimization for a real, steady bill.
  *Deferred on budget* (commitment spend). When adopted: cover the 24/7 floor only (mind the park/elasticity
  tension), start with Cost Explorer SP recommendations and 1-year no-upfront, graduate to longer/all-upfront as
  workloads stabilize.
- **Infracost Cloud** (paid tier) — central policy dashboards / org-wide cost governance on top of the free CLI.
  *Deferred on budget* — the free self-hosted CLI + PR comments cover the shift-left need today.
- **Vended FinOps platform** — *not deferred; rejected on principle* (see § Alternatives). Listed here only to
  be explicit that "future budget" does **not** reopen it.

## Consequences

### Positive

- A **coherent operating model** instead of scattered cost tools — every existing and future piece has a named
  home (phase + capability) and a maturity target.
- The platform's own cost becomes **honest and visible** (the `platform-shared` Scope), closing the gap ADR-091
  flagged and pre-empting the next CloudWatch-style surprise.
- **Reference-grade demonstration** of FinOps at small scale but correct shape — on-mission for a reference
  platform, and dogfoods the same governance fabric (owner-routing, PR gates, dashboards) we sell to tenants.
- **Small new surface** — most decisions are *adopt what's native/free* or *reuse what's built*; the only real
  net-new third-party tool is Infracost (OSS).

### Negative

- **More moving parts to operate** — Budgets, Anomaly Detection, Compute Optimizer, Infracost CI, and (if
  trialed) kube-green / Cloud Custodian each carry a small maintenance tax. Mitigation: prefer native + free,
  trial before adopt, and let the future FinOps agent (D7) absorb the toil.
- **The dollars are small.** ROI is measured in *demonstrated practice and avoided surprises*, not large
  savings. This must be stated plainly so the effort isn't mis-scoped as a big cost-cutting program.

### Risks

- **Savings Plans vs. elasticity tension** (a *future* risk — SP is deferred today, D6). When a budgeted
  successor does adopt commitments: a platform that parks overnight and scales to zero is the *opposite* of a
  stable commitment base — blanket Compute SP coverage would mean **paying for committed compute that's
  deliberately parked**. Mitigation: commit *only* to the genuine 24/7 floor (always-on system workloads that
  never park), analyze with Cost Explorer SP recommendations first, start 1-year no-upfront. Getting this wrong
  is a real way to *increase* cost — which is exactly why we document it before anyone buys.
- **Anomaly-detection noise.** ML anomaly alerts on a small, spiky, park-driven bill can false-positive on the
  expected nightly down/up swing. Mitigation: tune monitors per Scope, set sensible thresholds, route warnings
  (not pages) until calibrated — the same audit-first instinct as Kyverno.
- **CUR lag** (carried from ADR-091) — the true bill trails by hours-to-a-day; trend on OpenCost, *verdict* on
  CUR.
- **Tag-activation clock** — applying cost-allocation tags (#673) is forward-only with a ~24h lag and can't
  backfill; sequence it early so CUR data is usable when #668 lands.

## Alternatives considered

- **Fold platform cost into ADR-091.** Rejected — ADR-091 is tenant-scoped (per-team budgets/guardrails); the
  platform-shared Scope and the cross-cutting *practice/operating model* are a distinct governance domain.
  Bolting them onto the tenant ADR would blur the very allocation boundary ADR-091 depends on.
- **A vended FinOps platform.** Rejected — modeling cost in our own fabric is the demonstration; a second
  control plane is exactly what a reference IDP should show you *don't* need (and adds SaaS cost/lock-in).
- **Invent our own cost vocabulary.** Rejected — the FinOps Framework is the industry standard; adopting its
  Principles/Phases/Domains/Capabilities/Scopes verbatim makes the platform legible to any FinOps practitioner
  and is itself part of the reference value.
- **Stay ad-hoc (dashboards without a practice).** Rejected — that is the status quo that produced the
  CloudWatch `$356/mo` surprise; visibility without an operating model finds leaks on the bill, not before.
- **A FinOps agent first.** Deferred (D7) — automation belongs *after* the signals it would act on exist;
  building the agent before the budgets/anomaly/shared-cost surfacing inverts the dependency.

## Related

- [ADR-091](091-cost-guardrails.md) (the tenant Scope this sits above), [ADR-079](079-cloud-resource-monitoring-scope.md)
  (the monitoring backbone + CUR→Athena scope), [ADR-078](078-cluster-elasticity-karpenter.md) (Karpenter =
  the workload/idle lever), [ADR-084](084-platform-identity-directory-and-owner-resolution.md) (owner-routing =
  alert delivery), [ADR-082](082-platform-agent-runtime-xagent.md) / [ADR-074](074-agentic-workloads-platform.md)
  (the future FinOps agent + third-party-agent onboarding).
- Issues: [#668](https://github.com/asanexample/platform/issues/668) (CUR→Athena true spend), #673 (cost-allocation
  tags, merged-not-applied), #242 (orphaned EBS — a Cloud Custodian candidate).
- The `observability-opencost` module, the Backstage `cost` plugin, and the `cluster-parking` skill (the manual
  park D4 systematizes).
- [FinOps Foundation Framework](https://www.finops.org/framework/) (Principles, Phases, Domains, Capabilities,
  2025 Scopes).
