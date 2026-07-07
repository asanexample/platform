# Learn: Observability — Agent observability (deep dive)

> Assumes the [Observability orientation](orientation.md), especially **Stop 6** ("observing the observers")
> and the four-signal machine it rests on. This dive zooms into one area: how the platform observes its own
> **AI agents** — the triage copilot first — using OpenTelemetry's GenAI semantic conventions. If you just
> want the terse facts, the [Reference](reference.md#agent-observability-adr-076--live) has the one-paragraph
> version.

The orientation's metaphor was a **hospital patient monitor**: wire the patient up the moment they're
admitted, and read the vitals without the patient lifting a finger. An AI agent is a new *kind* of patient —
and the interesting thing is that the vitals you'd take for a web service (rate, errors, duration) tell you
almost nothing about whether the agent is *doing its job*. That gap is what this dive is about.

## The new problem: a non-deterministic worker

A `Deployment` is deterministic-ish: same request, same code path, same answer. You watch it with RED metrics
(Rate, Errors, Duration) and you know roughly how it's doing. An **agent** — here, the
[triage copilot](../../adrs/080-triage-copilot.md), which wakes on a critical alert, gathers evidence, and
proposes *"here's the likely culprit change and team"* — is a **non-deterministic, LLM-driven** worker. The
same alert can take a different path each time: a different number of model turns, a different set of tool
calls, a different confidence. "HTTP 200, p95 = 1.2s" is true and useless. The questions that actually matter
are new:

- **What did it cost?** Every model turn burns tokens, and tokens are money. A runaway loop isn't a 500 — it's
  a bill.
- **How long did the *whole decision* take**, across all its model and tool calls — not just one HTTP hop?
- **What did it actually do?** Which tools did it call, in what order, and did they succeed?
- **Was it any *good*?** Did a human accept its call, or correct it, or throw it away? A deterministic service
  is "up or down"; an agent can be *up and confidently wrong*, which no uptime probe will ever catch.

None of those fall out of Beyla's eBPF RED metrics. They need the agent to describe *its own reasoning loop*
in a vocabulary built for that shape. That vocabulary is the first thing to learn.

## Vocabulary, just in time: the GenAI semantic conventions

OpenTelemetry has a set of **semantic conventions** — agreed names for common attributes, so "duration" or
"http.method" means the same thing everywhere. In 2023–2025 the community added
[GenAI conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/): standard names for LLM/agent
telemetry — operations (`invoke_agent`, `chat`, `execute_tool`), token counts, model names, tool names, an
eval result. Adopting them means the platform's agents speak the *industry's* language, not a bespoke one.

The catch — and the reason for a design choice you should hold onto — is that this semconv is still
**`Development`-tier** (OTel's pre-stable status) and actively shifting; it has even graduated into its own
repo. So [ADR-076](../../adrs/076-agent-observability.md) (D1) wraps it: **all convention-specific attribute
mapping lives behind a single thin platform-owned instrumentation helper**, so when the spec renames a field,
that's *one edit* in the wrapper, not a fleet-wide rewrite. The agent's own code emits plain "input tokens";
the wrapper decides what OTel calls that this month.

> **Quick check:** why not just have each agent emit `gen_ai.usage.input_tokens` directly? *(Because the
> convention is `Development`-tier and drifting — pin it once in a wrapper so a spec change is a single edit.)*

## The one idea: the agent loop *is* a span tree

Here's the model to leave with. An agent's work is a **tree of nested operations**, and OTel's three GenAI
operation names map onto that tree exactly:

```mermaid
graph TD
  A["invoke_agent {agent.name}<br/>the whole triage"] --> B["chat {model}<br/>a model turn — tokens in/out"]
  A --> C["execute_tool {tool.name}<br/>query_logs, get_recent_changes, …"]
  A --> D["chat {model}<br/>another turn, given tool results"]
```

`invoke_agent` is the **parent span** over the whole invocation; `chat` spans are the individual model turns
(each carrying its token counts); `execute_tool` spans are the tool calls the model decided to make. This
isn't aspirational — it's live. Querying Mimir in-cluster for the operation-duration histogram's series shows
all three, from a real triage:

```text
$ wget -qO- --header 'X-Scope-OrgID: platform' \
    '<mimir-gateway>/prometheus/api/v1/query?query=count(gen_ai_client_operation_duration_seconds_count) by (gen_ai_operation_name)'
{"gen_ai_operation_name":"chat"} 1
{"gen_ai_operation_name":"execute_tool"} 1
{"gen_ai_operation_name":"invoke_agent"} 1
```

> **This is the flight recorder for a decision-maker.** A plane's flight-data recorder captures every input
> and control action so you can reconstruct *why* the aircraft did what it did — not just that it crashed. The
> `invoke_agent → chat → execute_tool` tree is exactly that: the reconstructable causal chain of one decision.
> **Where it breaks:** a plane's outcome is objective (it landed or it didn't); an agent's outcome — *was the
> triage good?* — is a human judgment. A flight recorder has no field for "the captain made a reasonable
> call." The agent's telemetry needs one, and that's the eval signal below.

## The attributes: doctor's notes *and* the bill — and there is no cost meter

On the spans hang the **`gen_ai.*` attributes** (ADR-076 D1, verified against the semconv): the provider
(`gen_ai.provider.name = "aws.bedrock"`), the request/response model, token usage
(`gen_ai.usage.input_tokens` / `output_tokens`), and — because this agent runs on a prompt-cached model — the
cache-aware counts `cache_read.input_tokens` / `cache_creation.input_tokens`. Tool spans carry
`gen_ai.tool.name` and `tool.call.id`; the loop carries `gen_ai.conversation.id`,
`gen_ai.response.finish_reasons`, and `error.type`.

Notice what is **absent**: there is **no cost metric** in the spec. That's deliberate, not a gap. Cost is
**derived** — `tokens × price(model@version)` — because the price isn't the agent's to know and changes
without the agent changing. That derivation *is* the [ADR-074](../../adrs/074-agentic-workloads-platform.md)
**metering seam**: the same tokens feed cost attribution. The dashboard's "Est. cost / day" panel does the
arithmetic in PromQL, pricing Sonnet 4.6 at $3 / $15 / $0.30 per million input / output / cache-read tokens.

> **The bill and the doctor's notes.** The **metadata** — tokens, latency, tool names, disposition — is the
> *itemised bill and the vitals chart*: cheap to keep, carries no patient data, and you keep it for
> *everything, always*. The prompt and response **content** is the *doctor's private notes*: kept only behind
> a privacy gate, never sold to an outside service. ADR-076 (D3) makes that split load-bearing —
> **metadata-first** is the default, and it's why cost/quality/latency all work *without* ever storing a
> prompt. **Where it breaks:** a bill still implies what happened; token metadata genuinely can't reconstruct
> the reasoning — for that you'd need the content, which is exactly the gated, deferred part.

## Instrument once, fan out per consumer — the three paths

The kernel of ADR-076 (as corrected by its 2026-06-27 amendment) is **instrument the agent once, then fan the
signal out to consumers that each want a *different substrate*.** An early draft said "one trace serves all
four consumers"; operating a live agent proved that wrong, and the amendment split it into three real paths:

**Path 1 — metrics, by Prometheus *scrape* (not OTLP push).** The agent exposes a `/metrics` endpoint and is a
plain **scrape target** — a Kubernetes `Service` on port `http` (container port **8080**) plus a
**`ServiceMonitor`** the platform's Prometheus picks up. Verified live:

```text
$ kubectl -n platform-agent-triage-copilot get servicemonitor triage-copilot-server -o yaml
spec:
  endpoints:
  - interval: 30s
    path: /metrics
    port: http
  selector:
    matchLabels:
      app.kubernetes.io/name: triage-copilot-server
```

Why scrape rather than push the metrics through the OTLP trace pipeline? **To isolate the two.** Metrics are
cheap, aggregatable, and want to keep flowing even if the trace collector is saturated or down; pulling them
on a separate scrape path means a metrics spike never rides — or stalls behind — the trace gateway. From here
they land in Mimir like every other metric.

**Path 2 — traces, by OTLP → OTel Collector → Tempo.** The `invoke_agent`/`chat`/`execute_tool` span tree,
enriched with the `gen_ai.*` attributes, flows over OTLP to the platform's OpenTelemetry Collector and into
Tempo — the **debug** consumer, where you open one triage and read its whole reasoning waterfall.

**Path 3 — durable eval / audit, by structured log → S3.** This is the sharp correction. The original ADR
claimed the *sampled Tempo trace* could double as the audit record. The amendment **withdraws** that: a
sampled, retention-bounded trace is **not** an audit record — you cannot audit on evidence that may have been
dropped or expired. So audit/eval gets its **own always-on, durable, write-once path** — structured records to
an S3 corpus (`platform-agent-eval-corpus`), which the agent's own [XAgent claim](../../adrs/082-platform-agent-runtime-xagent.md)
grants it `s3:PutObject`/`GetObject` on but **no `s3:DeleteObject`** (write-once integrity).

> **Quick check:** why can't the Tempo trace be the audit record? *(Traces are sampled and retention-bounded —
> the one you need for an audit may have been dropped or aged out. Audit needs a complete, durable path.)*

## The three slices — and the live token data behind them

ADR-076's build order shipped as three slices, all **live**:

**Slice 1 — the meter + the "Triage Agent (ADR-076)" dashboard.** Before this there was *no* agent meter at
all. Slice 1 added the token/latency/disposition/tool counters and the Grafana dashboard
(`agent-triage.json`, uid `agent-triage`)
that renders them (see the go-deeper links for the source). Real token counts flow today — a point-in-time
snapshot:

```text
$ ... 'query=sum(gen_ai_client_token_usage_sum) by (gen_ai_token_type)'
{"gen_ai_token_type":"input"}  6667
{"gen_ai_token_type":"output"}  259
```

(`cache_read` and `cache_creation` are in the schema and the cost panel; they simply have no series in this
small sample yet — designed-for, not yet exercised.) The disposition and tool-call counters are live too, and
they're refreshingly concrete about what the agent actually did:

```text
$ ... 'query=sum(triage_disposition_total) by (triage_disposition)'
{"triage_disposition":"insufficient_evidence"}  1

$ ... 'query=count(triage_tool_calls_total) by (gen_ai_tool_name)'
{"gen_ai_tool_name":"get_change_detail"}   1
{"gen_ai_tool_name":"get_recent_changes"}  1
{"gen_ai_tool_name":"query_logs"}          1
{"gen_ai_tool_name":"workload_status"}     1
```

**Slice 2 — span enrichment.** The span tree already existed (the agent was exporting `invoke_agent`/`chat`/
`execute_tool` before ADR-076); Slice 2 was *enriching* those spans with the `gen_ai.*` attributes so Tempo
carries provider, model, tokens, and tool names — an enrichment, not a greenfield build. (Note the split in
practice: on the *metric* series, provider/model aren't labels — that dimension lives on the *spans*, keeping
metric cardinality low. Query the metric and the provider/model labels come back empty; open the trace and
they're there.)

**Slice 3 — the eval online-signal.** This is the "was it *good*?" answer, and it's the part that makes agent
observability different from every other kind. When a human reacts to a triage in Slack — **Accept**,
**Correct**, or **Dismiss** — that verdict is recorded as a counter, `triage_feedback_total`, dimensioned by
`verdict` and by the agent's own `triage_disposition`. Two dashboard panels turn that into a **calibration**
signal: "Human verdicts" (volume over time) and, more sharply, **"Accept-rate by disposition"** —
`accept ÷ all verdicts`, per disposition. The teaching move is in that ratio: if the agent's *`confident_lead`*
triages get a *low* human-accept rate, the agent is **over-confident** — its confidence isn't calibrated to
reality. No token count or latency graph can tell you that; only the loop back to a human can.

## Show it break: the cold agent that isn't broken

Here's the failure mode you *will* hit, and it teaches the whole model. Open the agent dashboard right after a
deploy — or query the feedback counter — and it's **empty**:

```text
$ ... 'query=sum(triage_feedback_total) by (verdict)'
{"status":"success","data":{"result":[]}}
```

Empty. No series at all. Is the eval signal broken? **No** — this is verified-live *right now*, and it's
working exactly as designed. These are **zero-recording instruments**: an OTel counter emits **no time series
until it is first incremented.** `triage_feedback_total` has no series because **no human has rendered a
verdict yet** — the agent has triaged, but nobody has clicked Accept/Correct/Dismiss. Likewise the token and
disposition counters were empty until the agent's *first triage*. A genuinely cold agent shows only
`target_info` (the scrape-target heartbeat, which is present):

```text
$ ... 'query=count(target_info{namespace="platform-agent-triage-copilot"})'
{} 1
```

The self-heal isn't a fix — it's *use*. The first triage lights up the token/disposition/tool panels; the
first human verdict lights up the eval panels. An empty agent dashboard means **quiet, not broken** — the most
common false alarm in this whole area.

> **Quick check:** the disposition panel is flat and empty. Two possible causes — which do you check first?
> *(That the agent has actually run a triage since the last scrape reset — zero-recording instruments show
> nothing until first use — before you suspect the ServiceMonitor or the scrape.)*

## What's deliberately deferred — the honest edges

Being straight about built-vs-deferred is the point here, because this area is easy to oversell:

- **Content capture with per-tier redaction** — *deferred; metadata-only today.* Prompts/responses would only
  ever be stored behind a per-compliance-tier redaction gate and never shipped to a SaaS backend. And a hard
  invariant: **regulated tiers (hipaa/pci) are metadata-only *permanently*** — because reliable secret/PII
  redaction of free-form text is itself an unsolved problem, so the platform refuses to depend on it as a
  guarantee.
- **Langfuse (self-hosted LLM lens)** — *deferred, adopt-when-triggered.* A dedicated trace-tree/eval UX for
  LLMs; ADR-076 landed it as "adopt later," and the amendment flags it as a *reconsider-pulling-forward* now
  that a live agent with an eval harness exists. Today: OTel spans in Tempo, viewed in Grafana, are enough.
- **A2A (agent-to-agent) causality** — *designed, unexercised.* The plumbing propagates
  [W3C trace context](https://www.w3.org/TR/trace-context/) so a future multi-agent chain would be one
  correlated tree — but there's **one agent** today, so it's never been exercised.

## Gotchas that teach

- **Zero-recording instruments (the big one).** No series until first use. A cold agent = `target_info` only.
  Not broken — quiet. This is the single most common "the dashboard is empty" confusion.
- **No cost metric — cost is derived.** Don't hunt for `gen_ai_cost_total`; it doesn't exist by design.
  Cost = `tokens × model@version price`, computed in the dashboard's PromQL. Change the price, edit the panel.
- **Metrics scrape, traces push — on purpose.** Metrics come off a `/metrics` scrape (`:8080` +
  `ServiceMonitor`), not the OTLP trace pipeline, so a metrics load never stalls behind the trace gateway. Two
  paths, one instrumentation point.
- **A sampled trace is not an audit record.** The most instructive design correction in the ADR: audit/eval
  needs a *complete, durable, write-once* path (structured log → S3), because a retention-bounded, sampled
  Tempo trace can silently lose the very record you need.
- **Calibration lives in a *ratio*, not a count.** "Accept-rate by disposition" is where over-confidence shows
  up; raw token and latency graphs will look perfectly healthy while the agent is confidently wrong.
- **The convention will move under you.** GenAI semconv is `Development`-tier — that's *why* the mapping is
  wrapped. If an attribute name changes upstream, fix the wrapper, not fifty call sites.

## Go deeper

- **Sources of truth:** [ADR-076](../../adrs/076-agent-observability.md) (this design + its 2026-06-27
  correction) · [ADR-074](../../adrs/074-agentic-workloads-platform.md) (the data boundary + metering seam) ·
  [ADR-080](../../adrs/080-triage-copilot.md) (the agent being observed) ·
  [ADR-082](../../adrs/082-platform-agent-runtime-xagent.md) (the XAgent runtime that provisions the agent's
  namespace, Pod Identity, and scrape wiring).
- **The code:** the dashboard
  [`infra/modules/observability/dashboards/agent-triage.json`](https://github.com/asanexample/platform/blob/main/infra/modules/observability/dashboards/agent-triage.json)
  · the agent claim
  [`gitops/agents/triage-copilot.yaml`](https://github.com/asanexample/platform/blob/main/gitops/agents/triage-copilot.yaml)
  · the Agent Composition (which emits the namespace, Pod Identity, obs-read RBAC, and network policies)
  [`infra/modules/crossplane/charts/agent-api/files/composition.yaml`](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-api/files/composition.yaml)
  · the `/metrics` `ServiceMonitor` itself, which ships from the app repo's manifests via the per-agent ArgoCD
  ApplicationSet (declared as a managed kind in
  [`infra/modules/argocd-apps/agents.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/argocd-apps/agents.tf)),
  not the Composition.
- **Back to the whole machine:** the [Observability orientation](orientation.md); to *author* obs, the
  `observability-authoring` house skill; to author an agent, the `authoring-platform-agents` skill.
- **Substrate:** [OpenTelemetry GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
  (the vocabulary — note the `Development` status banner) ·
  [GenAI metrics spec](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-metrics/) (the exact
  `gen_ai.client.token.usage` / `operation.duration` histograms) ·
  [W3C Trace Context](https://www.w3.org/TR/trace-context/) (the standard behind the deferred A2A causality).
