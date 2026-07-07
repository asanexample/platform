# Learn: Observability — orientation

How the platform *sees itself* — how a slow request, a crash loop, a memory leak, or a runaway LLM bill
becomes something you can actually find and fix, and how little you had to do to make that possible. This is
the platform's senses: what it observes, how the signals get collected, where they live, how you jump between
them, and how they turn into a page at 3 a.m. — to the *right* person.

**Audience:** platform engineers, and any developer who's ever stared at a dashboard wondering *why*. Most of
this is platform-injected, so a developer gets the payoff without the plumbing — but understanding the
machine makes you far faster in an incident. **Before you start:** it helps to have seen
[Foundations](../foundations/orientation.md) (the cluster this runs on) and [Delivery](../delivery/orientation.md)
(what "a deploy" is). Know roughly what a metric, a log, and a trace are — we'll build up the rest.

## The question

It's 3 a.m. `alpha`'s `shop-web` is slow. A user complained. You have a laptop and a login. **What can you
actually find out — and what did the `shop` team have to do, ahead of time, to make it findable?**

Hold onto that second half, because it's the surprising part. On most platforms the answer is "a lot": the
team had to pick a vendor, link a metrics library into their code, wire up a tracing SDK, ship logs
somewhere, and hope they instrumented the right thing *before* the incident. Here the answer is **almost
nothing** — and that's not an accident, it's the whole design.

## The one idea: the platform observes your workload *for* you

Here's the thing to hold onto, because everything else is a consequence of it:

> **Observability here is a *property of the platform*, not a chore for the app. Your workload is watched
> from the moment it runs — four signals, collected mostly *zero-code* from below the process, stored
> together in one correlated stack on the platform's *own* storage, and turned into SLOs, pages, and cost
> attribution. You write almost no telemetry config; the platform injects it, the way it injects your
> securityContext and your AWS credentials.**

<!-- -->

> **The metaphor for the whole doc: a hospital's patient monitoring.** The moment a patient (your workload) is
> admitted, they're wired to monitors — heart rate, oxygen, blood pressure (the four signals) — *without the
> patient doing anything*. Every monitor feeds one **central nurses' station** (Grafana), where a clinician
> can glance from a vitals blip to the chart to the meds in one place (correlation). Alarms are tuned to page
> the *right* doctor, not the whole ward (SLOs + owner-routing). And the hospital owns its own monitors and
> records — it doesn't rent them from a company that keeps the data. **Where the metaphor breaks:** hospital
> sensors are external clip-ons; the platform's key sensor (eBPF, below) is wired *into the kernel underneath
> your process*, so it sees the inside of every request without touching your code. We'll flag the seams.

Now the tour, in the order the data flows: the **signals**, how they're **collected**, where they're
**stored**, how you **correlate** them, and how you **act** on them.

---

## Stop 1 — the four signals (what you can ask)

Observability rests on four kinds of signal, and the trick to using them is knowing which question each one
answers:

- **Metrics** — *numbers over time.* "What's the request rate? The error ratio? CPU? The p99 latency?"
  Cheap, aggregate, great for dashboards and alerts. Bad at "why *this* one request."
- **Logs** — *events with detail.* "What exactly happened at 03:04:17 in this pod?" Rich, high-cardinality,
  the place you read the actual error message.
- **Traces** — *the path of one request across services.* "Where did those 900ms go — the app, the database,
  the downstream call?" A trace is the waterfall of one request's journey.
- **Profiles** — *where the code spent its time.* "*Inside* the slow function, which lines burned the CPU?" A
  continuous flame graph of the running process.

Metrics tell you *something* is wrong and roughly where; traces tell you *which hop*; logs tell you *what*;
profiles tell you *which line of code*. The power isn't any one of them — it's having all four for the same
moment and being able to walk between them (Stop 4). This platform runs the **LGTM+P** stack:
**L**oki (logs), **G**rafana (the view), **T**empo (traces), **M**imir (metrics), **+ P**yroscope (profiles).

---

## Stop 2 — collection: watched from below, for free

Here's the design that makes the "3 a.m." answer *easy*. On most platforms, emitting these signals is the
app's job — link a library, wire an SDK, per language, and maintain it forever. Here it's **platform-injected**
([ADR-077](../../adrs/077-application-instrumentation-strategy.md)): the platform stands up the collectors and
instruments your workload without a line of app code, obeying the same paved-road rule as everything else.

The headline is **Beyla** — an **eBPF** agent running as a DaemonSet on every node. eBPF lets a program run
*inside the Linux kernel*, and Beyla hooks the kernel's networking and HTTP/gRPC/SQL paths. From watching
request *boundaries* down at the syscall level, it auto-generates **RED metrics** (Rate, Errors, Duration), a
**service graph**, and **request-level traces** — for **every workload, in any language, existing or future,
with zero code, zero manifest change, zero redeploy.**

> *Beyla is a traffic camera on the highway, not a GPS unit you install in each car.* It sees every vehicle's
> speed and route from the outside — so a Go binary, a Python service, and a vendored appliance you can't even
> recompile all light up identically, with nothing added. **Where it breaks:** a traffic camera sees the road,
> not the inside of the car — Beyla sees request boundaries, not your in-process function spans or custom
> attributes. That gap is exactly what the opt-in SDK layer fills (Stop 2b).

That gives an **instrumentation ladder** you climb only as far as you need:

- **Layer 0 — Beyla (eBPF), free and automatic.** RED metrics + traces + service graph for everything.
  **Live** across both clusters.
- **Layer 1 — the OpenTelemetry SDK, opt-in.** Want code-level spans and custom attributes? Add *one
  annotation* (`instrumentation.opentelemetry.io/inject-<lang>`) and the OTel Operator injects the SDK and the
  platform's OTLP endpoint at admission — no rebuild. *Honest status:* the operator is **live**, but no
  workload is wired to it yet (that's the golden-path rollout, P14 — still outstanding), so **today every app
  gets the Beyla baseline and no one has opted into Layer 1.*
- **Layer 2 — agent observability**, for AI agents (Stop 6).

Around Beyla sits a fleet of purpose-built collectors, each specialized for one signal (the
[collection deep dive](deep-dive-collection-and-instrumentation.md) covers them all): **Alloy** DaemonSets
tail each node's logs → Loki and eBPF-profile every process → Pyroscope; the **OpenTelemetry Collector**
receives OTLP traces → Tempo; **Prometheus** scrapes metrics → Mimir; a **CloudWatch exporter** pulls
AWS-side metrics (NAT, NLB, Transit Gateway) into the same pane. Your workload's only job for three of the
four signals is the oldest rule in the book — *log to stdout* — and even that's optional.

---

## Stop 3 — storage: one correlated stack, on your own S3

The signals land in the **LGTM+P** backends, and two design choices matter.

**First, it's self-hosted** ([ADR-043](../../adrs/043-self-hosted-observability-stack.md)) — the platform
runs Grafana, Mimir, Loki, Tempo, and Pyroscope itself, on its own **S3** buckets, rather than shipping
everything to Datadog or Grafana Cloud. Why? *A SaaS observability bill is a metered utility — the meter
spins on every host and every series, and at platform scale (many teams × many services × high cardinality)
that meter becomes the dominant platform cost.* Self-hosting is *owning the generator*: you pay compute you
already run plus cheap S3, your data never leaves your account (residency), and dashboards/alerts are
code in the repo (portability). The accepted trade is *"we operate it"* — but that's the reference platform's
whole thesis: own your stack.

**Second, the durable store is Mimir, not Prometheus.** Prometheus stays the *scraper* with only ~15 days of
local history; it **remote-writes every sample to Mimir**, which keeps the long-range history on S3
([ADR-044](../../adrs/044-mimir-durable-multi-tenant-metrics.md)). So you can lose and rebuild Prometheus
without losing history — the truth is in Mimir/S3. Same shape for the others: a small hot buffer on disk, the
durable blocks on S3.

**Tenancy** is worth one careful paragraph, because it's the subtle part. Every signal carries an
`X-Scope-OrgID` header naming a *tenant* — and each **cluster** is a tenant (`platform`, `preprod`), which is
how the hub keeps clusters' data separate. But here's the crucial security fact: **`X-Scope-OrgID` is a
*trust* header, not authentication** — the store delivers to whatever tenant the header names, like an
apartment number written on an envelope. So the *real* isolation boundary isn't the header, it's the
**network**: the `observability` namespace is default-deny, and the stores are ClusterIP-only — never on the
Gateway — so no tenant workload can even reach Mimir. (There's also a *per-team* tenant split, which is where
the honest-status caveat lives — Stop 5.)

**Topology: hub and spoke.** The `platform` cluster is the **hub** — it runs the collectors *and* the
backends. `preprod` is a **spoke** — it runs only lightweight collectors that ship their signals to the hub
over the Transit Gateway, through a write-only Gateway route that force-stamps the tenant (a spoke can't
spoof another). *The hub is a regional mail-sorting facility; a spoke is a neighborhood post office that
bundles its outgoing mail and ships it to the hub for storage.* The preprod spoke is **live for all four
signals** — real preprod apps (`alpha-shop`, `alpha-checkout`, `bravo-widgets`, …) are auto-instrumented by
Beyla and observable on the hub.

---

## Stop 4 — correlation: the jump

This is the *reason* to run five stores under one Grafana instead of five separate vendor tools: you can walk
from a symptom to its root cause **without leaving the pane**. That walk is wired into the datasources:

1. A **metric** spike on a dashboard carries an **exemplar** — a clickable dot linking to
2. the exact **trace** of a slow request, whose waterfall shows *which hop* was slow; from a span you jump to
3. that request's **logs** in Loki (the trace ID ties them together) to read the actual error; and from the
   span you jump to
4. the **CPU profile** — the flame graph showing *which function* burned the time (this works because Beyla's
   trace `service.name` and the eBPF profiler's `service_name` are deliberately aligned).

> *It's the hyperlinks in a detective's case file.* Each clue links to the next — the vitals blip → the ECG
> strip → the lab result → the tissue sample — four stores, one click each, never re-typing a query into a
> different tool. **This is the payoff of one correlated stack**, and it's live: RED spike → exemplar trace →
> its logs → its flame graph.

And rollouts overlay the graphs (deploy annotations), so "it got slow at 03:00" ties straight to "…because of
the 02:58 deploy."

---

## Stop 5 — acting on signals: SLOs, pages, and cost

Collecting signals is worthless if nothing *acts* on them. Three ways they turn into action, each with its
own [deep dive](deep-dive-slos-alerting-and-cost.md):

**SLOs — judging "good enough" by burn rate.** An SLO is a target (say 99.9% success) with an *error budget*
(the 0.1% you may spend). The platform generates **burn-rate** alerts — it pages not on a raw threshold but on
*how fast you're spending the budget*: a fast burn (budget gone in ~2 days) pages someone *now*; a slow leak
files a ticket for this week. *A threshold alert is a smoke detector that shrieks at burnt toast; burn-rate is
a fuel gauge with a trip-computer — it warns when your projected time-to-empty is short.* There's a
platform SLO on the API server, and — nicely — a **99.9% SLO is auto-derived for every prod app** straight
from its Environment claim, off its Beyla RED metrics.

**Alerts that page the *right* person.** ~40 curated alerts fire through Alertmanager, routed by severity
(critical → PagerDuty + Slack + SNS; warning → Slack; a always-firing *dead-man's switch* pages an external
service if the whole pipeline goes silent). But Alertmanager only knows *severity*, not *ownership* — so the
**triage agent** ([ADR-084](../../adrs/084-platform-identity-directory-and-owner-resolution.md)) resolves the
culprit's **team** from the git registries and pages *that team's on-call*, @-mentioning the commit author in
their Slack. *The fire panel shows the zone; the dispatcher looks up whose apartment it is and calls them.*

**Cost as an observable signal.** Two views, both in Grafana: **OpenCost** attributes in-cluster compute cost
per team/namespace in near-real-time (the *speedometer*), and a **true-cost exporter** pulls the *actual* AWS
bill from the Cost & Usage Report via Athena (the *odometer* — it includes discounts and Savings Plans the
speedometer's list prices don't). A budget enforcer can even block over-budget teams from provisioning
([ADR-091](../../adrs/091-cost-guardrails.md)). Cost becomes just another metric you can dashboard and alert
on.

---

## Stop 6 — observing the observers: agent observability

The platform runs AI **agents** now (the triage copilot), and they get observed too
([ADR-076](../../adrs/076-agent-observability.md)) — using OpenTelemetry's **GenAI semantic conventions**. One
instrumentation seam in the agent fans out to three consumers: **metrics** (token usage, operation latency,
dispositions) scraped into Mimir; **traces** (`invoke_agent` → `chat` → `execute_tool` spans, enriched with
`gen_ai.*` attributes) into Tempo; and a durable **eval** signal (the human's Accept/Correct/Dismiss verdict
as a counter) for measuring whether the agent is actually good. Cost is *derived* (tokens × model price).
This is **fully live** — real token counts flow today; content-capture and a dedicated LLM lens (Langfuse) are
deliberately deferred. It's the same four-signal machine, pointed at a new kind of workload.

---

## The honest status — what's live, and the one over-build

Because this is a portal that refuses to oversell (and because the audit will check): **almost all of it is
live.** The full data plane, the preprod spoke across all four signals, real instrumented apps, SLOs,
alerting + owner-routing, cost, and agent observability are all running and exercised.

The **one place to be careful** is *per-team* isolation. The per-team **write** split is real — metrics
genuinely land in separate `alpha` and `bravo` Mimir tenants (you can see their blocks on S3). But per-team
**read** isolation — a fail-closed proxy that would let `alpha` query *only* `alpha`'s data — is **deployed
and fail-closed but not actually used**: nothing points at it, and per-team *visibility* is delivered the
simpler way, through **namespace-filtered overview dashboards** (one dashboard per team, auto-generated from
the team registry). That's the honest picture: the hard isolation is a *superset* of the visibility that was
actually needed, built ahead of a consumer. The docs say so rather than claiming a "money shot" that isn't
wired up.

## When it breaks — the ones you'll actually hit

- **"My metrics/logs aren't showing up."** Isolation is by **network**, not the `X-Scope-OrgID` header — check
  your workload is in an instrumented namespace and the collector DaemonSet is healthy on its node; the stores
  are ClusterIP-only by design.
- **"Grafana can reach the app but a probe/backend can't."** The Cilium **`ingress` identity (8)** again — the
  `observability` namespace admits gateway traffic via a `CiliumNetworkPolicy` `fromEntities: ["ingress"]`
  (see [Foundations](../foundations/deep-dive-the-cluster.md)).
- **"The agent dashboard is empty."** Agent metrics are *zero-recording* instruments — they emit **no series
  until the agent's first action / first human verdict**. A cold agent shows only `target_info`. Not broken —
  just quiet.
- **"I expected per-team data isolation and don't have it."** See the honest status above — per-team *read*
  isolation is deployed but unexercised; use your team-overview dashboard.

## Recap — say it back

Try it cold: *how does the platform observe a workload, and what did the team have to do?* If you can say —

> "Almost nothing — it's **platform-injected**. Four signals — **metrics/logs/traces/profiles** — collected
> mostly **zero-code**: **Beyla eBPF** gives RED metrics + traces + a service graph for every workload from
> the kernel, with an opt-in **OTel SDK** layer for code-level detail. They're stored **self-hosted** in
> **LGTM+P** on the platform's own **S3** (**Mimir** is the durable metrics store Prometheus remote-writes to;
> isolation is by **network**, since `X-Scope-OrgID` is only a trust header), in a **hub-and-spoke** topology.
> One **Grafana** **correlates** them — metric spike → exemplar **trace** → its **logs** → its **profile**,
> one click each. Signals become action: **burn-rate SLOs** (incl. one auto-derived per prod app), alerts that
> the **triage agent routes to the owning team**, and **cost** as a first-class signal. Even the AI **agents**
> are observed (GenAI semconv). Almost all live; per-team *read* isolation is built but not yet wired" —

— then you hold the whole observability machine, and 3 a.m. is a series of clicks, not a mystery.

## Go deeper

- [The stack & storage](deep-dive-the-stack-and-storage.md) — the LGTM+P backends, S3, Grafana + SSO, the
  X-Scope-OrgID tenancy model, hub-and-spoke, and why self-hosted.
- [Collection & instrumentation](deep-dive-collection-and-instrumentation.md) — every collector, the eBPF
  zero-code story, the instrumentation ladder, platform-injection.
- [Correlation & the team experience](deep-dive-correlation-and-the-team-experience.md) — the metrics↔traces↔
  logs↔profiles jumps, the per-team dashboards, and the honest per-team-isolation story.
- [SLOs, alerting & cost](deep-dive-slos-alerting-and-cost.md) — burn-rate SLOs, curated alerts + owner-routing,
  OpenCost + true-cost.
- [Agent observability](deep-dive-agent-observability.md) — ADR-076, the GenAI semantic conventions, the
  live slices.
- The lookup: the [Reference](reference.md). Foundational context: [Foundations](../foundations/orientation.md).
