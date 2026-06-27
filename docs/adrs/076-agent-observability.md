# ADR-076: Agent / GenAI Observability

**Status:** Accepted (2026-06-18; corrected 2026-06-27)

> **Amendment (2026-06-27): the sequencing premise inverted, and the telemetry model is refined.** This ADR
> (2026-06-18) assumed the #102 backbone was *unbuilt* and that the **resource agent ([ADR-075](075-resource-agent.md))**
> would be the first telemetry producer that "pulls it into existence." Both are now false, and operating a *live*
> agent surfaced a design flaw. The decision still holds — OTel + GenAI semconv, one instrumentation point, the
> ADR-074 data boundary — but the following corrections supersede the corresponding parts of Context / D2 / D6 /
> "Dependencies & sequencing":
>
> 1. **Backbone is LIVE; the triage agent is tier-0.** The #102 backbone (Mimir/Loki/Tempo/OTel-Collector/Alloy) is
>    in production (P1–P7), and the **triage agent ([ADR-080](080-triage-copilot.md)) is the first agent** — live,
>    already exporting OTel spans (`invoke_agent`/`execute_tool`/`chat`) to the collector. The resource agent is still
>    at-rest. So "tier-0" re-anchors to the **triage** agent, agent obs is buildable **now** (gated on nothing), and
>    **this is an enrichment, not a greenfield**: the span tree exists; the gap is `gen_ai.*` attributes + a **meter**
>    (there is none today) + the disposition/eval signal.
>
> 2. **"One trace, four consumers" → "instrument once, FAN OUT per consumer."** The kernel (instrument once; no
>    parallel telemetry paths) stands, but the four consumers do **not** share a substrate: **debug** wants rich,
>    sampleable, short-retention **traces** (Tempo); **cost** wants aggregatable **metrics** (Mimir histograms);
>    **eval** wants discrete **events**; **audit** wants *complete, unsampled, durable* records. ⚠️ **A sampled,
>    retention-bounded Tempo trace is NOT an audit record** — D2's claim that "that same trace is … the audit record
>    (the no-bypass evidence of ADR-074)" is **withdrawn**. Audit gets its own always-on durable path (a structured
>    audit log), not the sampled trace. Net: one instrumentation point → traces (debug) + metrics (cost/quality) +
>    durable events (audit/eval).
>
> 3. **Reprioritized for an operating agent.** D2/D6 center the trace (debug). But the daily questions for a *live*
>    agent are **cost** (tokens/$) and **quality** (confidence calibration, abstention rate, hypotheses accepted vs
>    rejected) — both **metrics + the eval signal**. The first, highest-value slice is therefore the **meter +
>    a Grafana dashboard**, not the trace.
>
> 4. **Eval-online-signal is live now, not "deferred to the eval phase."** We have an eval harness
>    (`spike-triage-eval`) and the Slack human-confirm (the production accept/reject) — so the
>    `gen_ai.evaluation.result` loop (prod outcome → eval) is wired now.
>
> **Unchanged:** the GenAI-semconv wrapper (D1 — still `Development`-tier), metadata-first / in-cluster-only /
> secrets-never (D3; nuance: prompts already transit Bedrock, so the rule is "no SaaS-obs side-channel," not "content
> never leaves"). **Still deferred:** A2A causality (D5 — single agent), full content-capture-with-redaction (start
> metadata-only; free-form redaction is best-effort, as D3 admits). **Reconsider pulling *forward*:** the Langfuse
> LLM lens (D4) — we're iterating on a live agent with an eval harness now, so it may earn its keep before the
> multi-agent phase D4 assumes.
>
> **Build order (triage agent):** (1) **meter + dashboard** (token/cost/latency/disposition/tool metrics →
> Mimir/Grafana); (2) **enrich the existing spans** with `gen_ai.*` attributes (Tempo); (3) the **eval-online-signal
> loop**. Defer content-capture, Langfuse, A2A.

## Context

[ADR-074](074-agentic-workloads-platform.md) makes agents a first-class, governed workload class. Observing them
is named there only in passing — "adopt OpenTelemetry GenAI tracing," "two-stream logging," "causality-aware" A2A
tracing — but never designed. Agents have observability needs ordinary workloads do not: a single request fans out
into model calls, tool calls, a proposed artifact, a policy-gate verdict, and a human decision, and we need to see
that whole causal chain to debug it, attribute its cost, feed its outcome back into evaluation, and audit it.

The platform's *metrics/logs/traces backbone* is already a decided design — [ADR-043](043-self-hosted-observability-stack.md)
(kube-prometheus-stack) + [ADR-044](044-mimir-durable-multi-tenant-metrics.md) (Mimir), with logs/traces (Loki,
Tempo), the collector tier (Grafana Alloy + OpenTelemetry Collector), per-tenant isolation, collector-side
secret/PII redaction, and trace↔logs↔metrics correlation all specified as later phases of `docs/plans/102-observability-stack.md`
(P3/P6/P7). That backbone is unbuilt but not undecided. **This ADR does not redesign it.** It rides it, and decides
only the agent/GenAI-specific layer on top.

This is also where three threads we already have converge on one telemetry path: the ADR-074 **cost metering seam**
(per-tenant token/cost), **eval-as-a-service online signals** (did the proposed artifact get accepted), and
**AgentOps debugging** all read the same per-invocation trace. The point of treating this head-on is to instrument
once, not three times. A de-risking spike confirmed the practical caveat: the OpenTelemetry **GenAI semantic
conventions are still experimental** as of 2026 and the ecosystem is split between OTel-GenAI (metrics) and
OpenInference (traces) — so the convention must be isolated behind our own thin instrumentation seam.

## Decision

Adopt **OpenTelemetry as the instrumentation standard and the GenAI semantic conventions as the agent vocabulary**,
emitted into the platform backbone (Alloy/OTel Collector → Tempo/Loki/Mimir, federated per-cluster). Model each
agent invocation as **one correlated trace that serves four consumers — audit, eval online-signal, cost
attribution, and debugging — instrumented once.** Govern what content enters telemetry with the **ADR-074 data
boundary**: metadata always, prompt/response content only under a per-compliance-tier redaction gate and never off
cluster, secrets never. Hold zero standing dependency on any SaaS observability backend.

## Design

### D1 — Standard: OpenTelemetry + GenAI semantic conventions, behind a wrapper

We instrument agents with OpenTelemetry and the GenAI semantic conventions (model, token usage, cost, latency,
tool calls). Because that semconv is still experimental and partially contested (OTel-GenAI vs OpenInference), all
convention-specific attribute mapping lives behind a **single thin instrumentation helper** owned by the platform,
so a convention change is one edit, not a fleet-wide rewrite. Vendor-neutral; no lock-in. This is consistent with
the OSS-default, capability-not-vendor stance of ADR-043 and the build-vs-adopt ladder of ADR-074.

**Concrete schema (verified against the OTel GenAI semconv, 2026).** Status is **`Development`** (OTel's pre-stable
tier) and the spec has **graduated into its own repo** (`open-telemetry/semantic-conventions-genai`) — active, but
still shifting, so the wrapper stays. The pieces we pin:

- **Operations** (`gen_ai.operation.name`, *required*): `invoke_agent`, `chat`, `execute_tool` (also `create_agent`,
  `invoke_workflow`, `embeddings`). These map 1:1 to our loop — an **`invoke_agent {agent.name}`** parent span over
  child **`chat {model}`** and **`execute_tool {tool.name}`** spans.
- **Attributes**: `gen_ai.provider.name="aws.bedrock"` (set at span creation), `gen_ai.request.model` /
  `response.model`, `gen_ai.usage.input_tokens` / `output_tokens` plus **`cache_read.input_tokens` /
  `cache_creation.input_tokens`** (prompt-cache-aware), `gen_ai.agent.name`/`id`, `gen_ai.tool.name` (*required*) /
  `tool.call.id`, `gen_ai.conversation.id`, `gen_ai.response.finish_reasons`, `error.type`.
- **Content is `Opt-In` in the spec itself** — `gen_ai.input.messages` / `gen_ai.output.messages` /
  `gen_ai.system_instructions` default OFF and may be emitted as a **separate event decoupled from the trace**. This
  *validates D3 by construction*: metadata-first is the spec default; content is the deliberate opt-in, and decoupling
  it as an event lets us route content to a separate sink with its own retention/redaction.
- **Metrics**: `gen_ai.client.token.usage` (histogram) + `gen_ai.client.operation.duration` (histogram). **There is no
  cost metric** — cost is *derived* from tokens × `model@version` price, i.e. exactly the ADR-074 metering seam.
- **Eval as a first-class event**: the semconv defines a **`gen_ai.evaluation.result`** event
  (`gen_ai.evaluation.name` / `score.value` / `score.label` / `explanation`) — a native carrier for our eval verdict,
  so the eval-online-signal consumer (D2) rides a standard event rather than a bespoke field.

### D2 — Telemetry model: one trace, four consumers

Each agent invocation is one trace — a span tree over: elicitation turns → model calls (tokens in/out, cost,
latency, `model@version`, cache hits) → tool calls → the emitted artifact (e.g. the claim) → the **policy-gate
verdict** → the **human-confirm decision** → final disposition (proposal merged / abandoned). That same trace is
simultaneously:

- the **audit record** (who/what/when, the no-bypass evidence of ADR-074),
- the **eval online-signal** (was the proposed artifact accepted — feeds eval-as-a-service),
- the **cost-attribution record** (the ADR-074 metering seam — per agent / tenant / model), and
- the **debug record** (the causal chain when something goes wrong).

Instrumenting this once, with stable span/attribute names, is the load-bearing decision — it is why the metering,
eval, and AgentOps efforts do not each build a parallel telemetry path. The full span tree is the **designed-for end
state**; **tier-0 emits only a minimal subset** (proposal accepted/abandoned + token/cost) — see D6.

### D3 — Content capture is governed by the ADR-074 data boundary

Observability wants to store prompts, responses, and context for debugging; ADR-074 holds that context is an
authorization boundary, secrets never enter context, and egress is gated per compliance tier. Telemetry inherits
those rules verbatim:

- **Metadata is always captured** — tokens, cost, latency, `model@version`, tool names, verdicts, disposition.
  This carries no tenant data and powers cost/eval/audit without exposing content.
- **Prompt/response/context content is captured only behind a per-compliance-tier redaction gate** (the same
  collector-side redaction the #102 plan already specifies), and is **stored in-cluster only — never shipped to a
  SaaS observability backend.**
- **Secrets in telemetry is a hard never** (an invariant, not a tier knob), mirroring secrets-never-in-context.
- **Regulated tiers (ADR-013 hipaa/pci) default to metadata-only** — content capture off, because reliable secret/PII
  redaction of free-form prompts/responses is itself an *unsolved, best-effort* problem (the same class as
  prompt-injection detection); we do not rely on redaction as a guarantee. Content-with-redaction is opt-in and
  best-effort, in non-regulated tiers only.

This per-tier content rule is what makes this an *agent* observability decision rather than a generic one.

### D4 — Storage: the existing self-hosted backbone; the LLM lens is deferred

Traces land in **Tempo**, logs in **Loki**, metrics in **Mimir**, federated per-cluster exactly as the #102 plan
specifies — no new store. A dedicated agent/LLM lens (trace-tree UX, evaluation, human annotation) — **Langfuse,
self-hosted (MIT)** — is **deferred to the multi-agent / eval phase** (the build-vs-adopt component spike landed it
as adopt-when-triggered, not now); it would consume the same OTel stream. At tier-0, OTel spans → Tempo viewed in
Grafana is sufficient. The in-cluster-only constraint of D3 rules out SaaS LLM-observability backends regardless.

### D5 — Causality across agents (A2A)

Agent → tool → agent calls propagate **W3C trace context**, so a future autonomous multi-agent chain is one
correlated trace tree (the "causality-aware" tracing ADR-074 calls for). Designed-for now; exercised when A2A
exists.

### D6 — Tier-0 scope vs designed-for

Tier-0 (the resource agent, ADR-075) builds the minimum: emit GenAI spans + metrics (tokens/cost/latency/verdict/
disposition) into the existing collector → Tempo/Grafana — which **is** the ADR-074 metering seam, not a second
mechanism. Deferred to later phases: the Langfuse lens, full A2A causality, the human-annotation pipeline, and
drift dashboards.

## Dependencies & sequencing

This ADR rides the platform traces/logs backbone (#102 P3 Loki/Tempo/OTel-Collector/Alloy; P6 APM; P7
auto-instrumentation). That backbone is **decided but unbuilt**; building it is tracked under epic #102 and is the
prerequisite to realizing agent tracing. Nothing here mandates standing it up ahead of need — the tier-0 build
(ADR-075) is what pulls the minimum backbone into existence.

## Consequences

- One instrumented trace serves audit, eval, cost, and debugging — the telemetry path is built once.
- Agent telemetry inherits the ADR-074 data boundary, so observability cannot become a side channel that leaks
  context or secrets, and regulated tiers stay metadata-only.
- We take on the experimental-semconv risk, contained behind the D1 wrapper.
- The agent LLM lens (Langfuse) is a known, deferred adopt — no decision debt.
- Realizing any of this depends on the #102 backbone being built; until then this is a documented design, not a
  running capability.

## Alternatives considered

- **Fold agent observability into ADR-074 or the #102 plan** — rejected: ADR-074 is merged and append-only, and
  #102 is platform-observability; agent/GenAI observability (GenAI semconv + the data-boundary content rule + the
  per-invocation agent trace model) is a distinct enough domain to own its ADR.
- **A SaaS LLM-observability product (hosted Langfuse / Phoenix / Braintrust)** — rejected: the D3 in-cluster-only
  content rule and the OSS-default posture forbid shipping prompt/response content off-account; a self-hosted lens
  is the only fit, and it's deferred regardless.
- **OpenInference-only (skip OTel-GenAI)** — rejected: couples us to one vendor's convention; OTel-GenAI is the
  vendor-neutral standard we already align to, and the D1 wrapper absorbs the convention churn.
- **No first-class agent observability (rely on the generic metrics stack)** — rejected: metrics dashboards cannot
  express the per-decision causal chain agents need for debugging, audit, eval signal, or cost attribution.

## Related

[ADR-074](074-agentic-workloads-platform.md) (agent substrate — data boundary, eval-as-a-service, metering,
kill-switch audit) · [ADR-075](075-resource-agent.md) (tier-0 agent — first telemetry producer) ·
[ADR-043](043-self-hosted-observability-stack.md) + [ADR-044](044-mimir-durable-multi-tenant-metrics.md) +
`docs/plans/102-observability-stack.md` (the backbone this rides) · [ADR-013](013-compliance-tier-model.md)
(compliance tiers drive the D3 redaction gate). Epic: #102.
