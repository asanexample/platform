# ADR-080: The Triage Copilot — Propose-Only On-Call Incident Triage, and the Observability Stack's First Real Workload

**Status:** Accepted (2026-06-24) — agent built + live

## Context

The observability backbone is **built and live** — [ADR-077](077-application-instrumentation-strategy.md) records that
metrics, logs, traces (Loki/Tempo + the Alloy/OpenTelemetry-Collector tier), alerting, cloud-resource metrics, and
in-cluster cost are all running (`docs/plans/102-observability-stack.md` P1–P5/P11), and that Beyla eBPF + the OTel
Operator auto-inject give every workload RED metrics + request-level traces for free. But that same ADR found the
uncomfortable truth: a live check saw **zero spans flowing through Tempo, because nothing instruments the workloads.**
The remaining high-value phases — **P6 APM** (service graph), **P9 SLOs**, **P13 per-team isolation**, and the
**trace↔logs↔metrics↔profiles correlation drills** — have a backbone but **no input.** We have built an instrument and
never played a note.

So we want a **real application that produces rich, realistic telemetry across every signal** — not a throwaway demo,
but something the team genuinely uses, whose architecture *naturally* emits metrics, logs, traces, profiles, alerts,
and correlations. The selection criterion is **telemetry coverage per unit of build effort, married to real utility.**
Surveying candidates (an IDP slice, a FinOps portal, a generic multi-service product), the richest possible workload —
and the one that doubles as roadmap progress — is **an agent.** Agent invocations fan out into model calls, tool
calls, async work, and downstream queries; they carry token/cost metrics, long causal traces, variable CPU, and a
measurable quality signal. No other candidate lights up as many signals.

This decision is the **concrete demand** the agentic thread was waiting for. [ADR-074](074-agentic-workloads-platform.md)
established the Agentic Workloads substrate and deliberately left it **at rest pending a real pull**; the resume trigger
recorded for it is *"a concrete wanted agent."* This is that agent — and we choose to make it the **first agent built on
the substrate**, ahead of the resource agent ([ADR-075](075-resource-agent.md)), because it is the agent we have real
demand for and the **best observability-exercising workload** while being a genuinely useful on-call tool.

That choice **revises the ADR-074/075 sequencing** with eyes open. Those ADRs put the resource agent first *precisely
because* it is oracle-able and low-stakes — the deliberate easy pipe-cleaner. Building the triage copilot first means the
substrate's **very first proof is the harder, no-oracle case** (D6), which front-loads the eval risk and makes the
retrospective-harness spike doubly load-bearing — it is now the substrate's *first* eval mechanism, not just this agent's.
We accept that trade for the demand and the observability payoff; the resource agent remains a valuable **complementary,
later** build whose clean deterministic oracle is still a worthwhile separate substrate check.

Be clear-eyed about the hard part. The resource agent was a deliberately *oracle-able* proving ground — its artifact
(the claim) is machine-checkable and the deterministic form is its oracle. **The triage copilot has no such oracle:**
there is no deterministic function from "alert + telemetry" to "correct root cause." That is exactly the risk flagged
when this thread was parked — **evaluating an agent without an oracle** — and it is the load-bearing problem this ADR
must answer, not wave at (see D5).

## Decision

Build the **triage copilot**: a **channel-agnostic, propose-only, zero-infrastructure-privilege** agent that, on an
alert, **reads** the observability stack (Mimir/Loki/Tempo) plus k8s and recent-deploy state, **correlates** the
evidence into a ranked set of hypotheses, and **proposes** a structured triage — summary, linked evidence, likely
cause, suggested next step — to a human incident surface. **It never remediates; it only proposes.** It is **tier-0
on the action axis** (propose-only, zero standing infra privilege, worst case is an ignored Slack message), and it is
the **first real, telemetry-rich application** the observability backbone has had to ingest.

It is deliberately built as a **small multi-service system** (ingest → runner → eval-scorer, with a datastore, a
cache, and an async queue) — not because the agent logic demands every piece, but because that topology is what
exercises cross-service traces, queue-lag metrics, and the full correlation drill end-to-end. We state that motive
plainly rather than smuggle it in.

**What this ADR commits to vs. records as direction.** *Firm — accept now:* propose-only / zero-infra-privilege;
read-only least-privilege identity; the retrospective-replay eval as the primary quality gate (D6); the data boundary
for reading operational telemetry (D5); the kill-switch → human-direct fallback. *Directional — re-decided before
build:* the precise hypothesis-ranking method, the channel set beyond the first adapter, and the agent's runtime
shape (standalone service vs. a first-class `Agent` CRD — the same shape question ADR-074/075 leave open). The
**in-cloud model host** (Bedrock on AWS, behind a provider seam — D5) is firm; the **model *tier*** (D8) is directional.

## Design

### D1 — What it triages (scope of the agent's job)

On an **Alertmanager webhook**, the agent:

1. **Scopes** the blast radius from the alert labels (service, namespace, severity, window).
2. **Gathers** evidence with read-only queries — the firing series and neighbours (PromQL/Mimir), correlated logs for
   the window (LogQL/Loki), exemplar/error traces (Tempo), pod/event/rollout state (k8s read), and **recent changes**
   (D2) — which are the single highest-signal correlate for "what just broke."
3. **Correlates** into a small ranked set of **hypotheses** ("error rate tracks the 14:02 deploy of `payments@a1b2`;
   p99 latency and the DB connection-pool-saturation metric co-move"), each with the **evidence links** that support
   it (deep links into Grafana/Tempo, not prose).
4. **Proposes** a structured **triage card** to the incident surface — summary · ranked hypotheses · evidence · a
   suggested *next diagnostic step* (never an executed remediation) · confidence.

That is the whole job: **shorten the time from "alert fired" to "human knows where to look."** It is read-and-propose;
the human acts.

### D2 — Change correlation (the highest-yield tool, first-class)

Most incidents are **change-induced**, so the agent does not stop at *"a deploy happened"* — correlating the failure to
**what changed** is its single strongest heuristic and gets first-class treatment:

- **Deploy/PR correlation** — find the PR/commit whose rollout window (ArgoCD sync) straddles the alert; surface the PR
  link + changed-files list. Cheap, low-risk, high-signal.
- **Read the diff** — pull the diff of the correlated change, **scoped** to the affected service + window, so the agent
  can point at likely-culprit lines rather than a bare "something deployed."
- **Join the failure signature to the change** — e.g. a Tempo stack-frame in `payments.Charge()` against a 14:02 PR that
  modified `payments.Charge()` is a near-certain lead. This **telemetry↔source-change join** is the strongest single
  signal the agent produces.
- **"Change" is broad** — app-code diffs **and** GitOps/manifest edits **and** Kyverno-policy changes, since config
  breaks as often as code (and the platform is GitOps-heavy). All are "what changed" candidates.

Source diffs are **content** (D5): they enter context only via the in-cluster/in-account model, never an external one,
and the secrets-never invariant holds (a secret accidentally committed in a diff must not be re-surfaced). This
capability also happens to be the **most oracle-able part of the triage** — historical incidents usually have a known
culprit change — which is why D6's replay set grades it directly.

### D3 — Topology (the telemetry-maximizing architecture)

A **channel-agnostic core** behind thin surface adapters (first adapter: Slack / the incident channel; PR-comment and
Backstage adapters later). The deployable shape:

- **ingest** — receives the Alertmanager webhook, dedupes/groups, enqueues. (HTTP RED metrics; queue-publish spans.)
- **runner** — the agent loop: model calls + tool calls (the D1 queries), emits the triage. (The rich agent trace.)
- **eval-scorer** — consumes outcomes + runs the retrospective harness (D6). (Batch + online; its own CPU profile.)
- **datastore** (CNPG, per ADR-051 pattern) — runs, hypotheses, evidence, human feedback. (DB spans, pool metrics.)
- **cache** — context/dedup + query-result memoization. (Cache-hit metrics, fast spans.)
- **queue** — ingest→runner async path. (Queue-depth/lag metrics, **async trace-context propagation.**)

Every piece is a real part of a robust triage service *and* a deliberate generator of a distinct telemetry shape. The
generic signals (RED, traces, DB/queue) arrive **for free** via the ADR-077 platform-injection path (Beyla + OTel
auto-inject); only the **agent/GenAI-specific** signals are hand-instrumented, via the ADR-076 wrapper (D7).

**Placement:** the agent is **platform infrastructure** — platform-team-owned, reading cross-tenant telemetry, running
on the platform cluster — so it sits *outside* the per-Product Kyverno envelope / environment-namespace tenant model
(it's a platform-system workload like the obs stack itself, not a tenant environment workload). *(ADR-081 briefly routed
the agent through the tenant Environment model, landing it on preprod where its hub-resident obs is unreachable;
[ADR-082](082-platform-agent-runtime-xagent.md) restores this D3 intent via the purpose-built `XAgent` runtime — the agent
is `XAgent` #1, hub-placed, provisioned by the agent Composition, not the tenant one.)*

### D4 — Identity & authority (zero infrastructure privilege)

The agent holds a **least-privilege, read-only** identity (Crossplane-derived EKS Pod Identity, ADR-041/047), scoped
to exactly: the **query** APIs of Mimir/Loki/Tempo, **k8s read** (`get`/`list`/`watch`, no write/exec), and
**read-only** ArgoCD/GitHub deploy history. **No write, no exec, no remediation verb anywhere in its grant** — the
propose-only invariant is enforced by the *absence of capability*, not by prompt discipline. Its only write is posting
a message to the incident surface. This is the ADR-074 "propose, don't act" model with the smallest possible authority.

### D5 — Data boundary + model hosting (the new concern)

The resource agent only read a Team's own envelope. The triage copilot reads **production operational telemetry**,
which may carry tenant content (log lines, trace attributes) across tenants — a content-exposure surface ADR-075 never
had. It inherits the [ADR-074](074-agentic-workloads-platform.md) data boundary and the [ADR-076](076-agent-observability.md)
D3 rules **verbatim, on the read side:**

- **Metadata-first by default** — metric series, trace/span metadata, structured-log *fields*, deploy facts, k8s
  status. This is enough for the great majority of triage and carries no free-form content.
- **Raw log/trace *content* enters the agent's context only behind the per-compliance-tier redaction gate**, stays
  **in-cluster** (the model endpoint is in-account / in-cluster — never ships content to a SaaS model or obs backend),
  and **regulated tiers (ADR-013 hipaa/pci) are metadata-only** — content off, because reliable PII/secret redaction of
  free-form telemetry is best-effort, not a guarantee.
- **Secrets in context is a hard never.** The agent's *own* outputs and reasoning are themselves telemetry under the
  same boundary (D7) — observability cannot become a side channel.

**Model hosting is forced by this boundary, not a free choice.** Because raw telemetry and source diffs (D2) enter the
model's context, the model endpoint must be **in-cloud / in-account** — the public Anthropic API is ruled out for the
content path (even with Workload Identity Federation, content still leaves the cloud). On AWS that means **Amazon
Bedrock** (AWS-operated, in-region, not used for training; auth is **SigV4/IAM straight onto the agent's EKS Pod
Identity** — no API keys to vault, matching ADR-041/047).

**The model is reached through a thin `Model` port we own — never a vendor SDK.** The runtime depends only on a small
internal interface (system + messages + a forced tool/schema → structured result + token usage); each provider is an
*adapter* behind it, swappable by config. This delivers vendor- and **local-model** portability and avoids any hard
dependency on a model-vendor SDK:

- **First adapter: the Bedrock `Converse` API via `aws-sdk-go-v2`** — *not* the Anthropic SDK. Converse is one API
  shape across **all** Bedrock models, so swapping Claude ↔ Llama/Mistral/Titan is a model-id change; `aws-sdk-go-v2` is
  already a platform-wide dependency (no new vendor lib); it's AWS-native (Pod Identity); and it carries `toolConfig`
  (force the structured-output tool), `usage` (incl. cache tokens), and the validated `us.anthropic.claude-sonnet-4-6`
  inference-profile id.
- **Portability map:** Bedrock Converse now → an **OpenAI-compatible adapter** (covers local Ollama/vLLM, OpenAI,
  OpenRouter) and **Vertex / Foundry** adapters when a second model or cloud is actually wanted. Build the port + one
  adapter now; defer the rest (no speculative provider zoo).
- **Trade-off:** Converse is lower-level than a Claude SDK (no provider `strict` mode), so structured output is enforced
  by **schema validation + retry in our code** — which is more portable (other vendors/local lack strict mode) and which
  our grader's taxonomy validation already half-implements.
- The **OTel GenAI instrumentation wrapper (ADR-076 D1) sits at this port boundary**, so every adapter is instrumented
  identically — one wrapper, all providers.

Content stays pinned to the host cloud and (for regulated tiers) region; **metadata-only-to-the-public-API** is the
regulated-tier degrade.

This per-tier read rule — plus the in-cloud model constraint it forces — is what makes this an *agent* observability
decision and not a generic dashboard.

### D6 — Evaluation: manufacturing an oracle by breaking things on purpose

The triage copilot has **no deterministic oracle** — there is no lookup from "alert + telemetry" to "correct root
cause," and a confidently-wrong RCA is the dangerous failure (it misdirects responders and *lengthens* the outage).
Measuring quality is therefore the riskiest part of the build, and the eval harness is the **first thing prototyped
(the gating spike), not the last.** And we **cannot mine the answer key from history**: dev telemetry retention is
~15 days, so the data behind any older incident is already deleted. The corpus must be **built forward**, from three
sources:

- **Fault injection — the bootstrap and the spike's real deliverable.** Deliberately inject a *known* failure in a
  walled-off preprod namespace; the root cause is ground truth **because we caused it**, and we control timing so the
  telemetry window is clean. This is the only source that yields a large, cleanly-labeled corpus **on demand, before
  the agent runs in prod.** It maps onto what already exists — the ~29 curated P4 alerts plus common app failure modes
  (bad-deploy crashloop, OOM, dependency latency, config error, Cilium policy-deny, cert/secret failure, pool
  exhaustion). The harness is **reusable, not throwaway**: it becomes the **regression suite** (re-run on every
  prompt/model/tool change, in CI) and doubles as another exercise of the observability stack.
- **Historical postmortems — realism supplement.** The handful of real incidents with a recorded RCA (the
  fixing/reverting PR); sparse, noisy, prose labels, useful only forward or within retention.
- **Production shadow — the long tail.** Once live, every real triage + the human accept/correct/dismiss + the
  eventual RCA becomes a new labeled case (this *is* the online signal, below), accruing slowly.

**Replay = freeze fixtures, not keep backends hot.** At injection time, **snapshot** the telemetry the agent would
pull into a frozen fixture `{alert-group, telemetry snapshot, structured label, rubric}`; replay feeds the agent the
fixture, not live backends. Deterministic, CI-able, and it survives the 15-day retention (we kept a copy). The
"a photo can't answer an off-script query" gap is closed by the **deterministic context-pack (D1)** — we know exactly
what to snapshot, plus a broad raw window for the bounded follow-ups. Long-retention live-backtest is the deferred
upgrade, not the start.

**Grading = a structured taxonomy, so scoring is set-membership, not judgment.** Both the recorded label and the
agent's hypotheses fill the **same form** — `{culprit_service, culprit_change (deploy/config/infra/dependency/none),
failure_class (crashloop/oom/latency/dependency_timeout/policy_deny/cert_expiry/saturation/config_error/…)}`.
Automatable scores: **top-1 / top-3 culprit-service**, **failure-class accuracy**, and — the strict gate —
**change-attribution** (fault injection always has a known culprit change, and change-correlation (D2) is the most
oracle-able part). **`pass^k` consistency** replays each fixture *k* times and fails on flapping. LLM-judge for
*explanation* quality stays deferred. **Calibration is scored, not just correctness** — a correct *abstention* (D10) on
a hard/novel case scores well; a **confident-wrong** RCA scores *worse than* an abstain.

**Online outcome signals** (the production eval, cheap and continuous): human accept/correct/dismiss, did-the-cause
match the eventual RCA, MTTA/MTTR delta on triaged vs. untriaged alerts. Qualitative at first (no baseline), hardening
as data accrues.

**Honest gaps — recorded, not papered over.** (1) Fault injection only covers *known* failure modes; it cannot
manufacture the *novel* incident, which is exactly where the agent's value and risk live — so injection accuracy is a
**regression floor, not a measure of novel-incident performance**, and only the (weak) online signals proxy novel.
(2) Injected faults can be **too clean**; mitigate by injecting **compound faults under k6 load** for realistic noise.
(3) Snapshot fidelity is bounded by what we capture — the window + query set is recorded with each fixture.

The full spike (scenarios, build checklist, GO/NO-GO) is `docs/plans/080-triage-copilot-eval-spike.md`.

**Spike executed 2026-06-24/25 → GO** (results in the plan doc): the eval mechanism works end-to-end on real injected
telemetry plus a 12-fixture corpus on Bedrock, the agent abstains on healthy data rather than bluffing, and D2
change-correlation (ArgoCD + GitHub) is wired and empirically confirmed as the highest-yield signal. The agent build is
de-risked to proceed; the ADR stays **Proposed** until that build is actually pulled.

### D7 — Observability of the agent itself (rides ADR-076 — and closes the loop)

The agent is the **first real producer** of the [ADR-076](076-agent-observability.md) one-trace-four-consumers model:
each invocation is one trace over *alert-ingest → model calls (tokens/cost/latency/`model@version`) → tool calls (each
obs query a child span) → emitted triage → human accept/correct/dismiss → outcome*, serving **audit, eval-signal,
cost-attribution, and debug** at once, via the single GenAI-semconv wrapper. It validates ADR-076 end-to-end with live
data instead of a paper design. The loop is deliberately self-referential: **the agent queries the observability stack
while being observed by it** — the richest possible exercise of the correlation drills (one alert → the agent's own
trace → its tool spans → correlated logs → its token-cost metric → its CPU profile).

### D8 — Lifecycle, safety, runtime

Composite **signed release** `{image, prompt@v, model@v pinned, tools@v}` with elevated review on the prompt/tool-set
(ADR-074 lifecycle). **Kill-switch → fall back to "no triage, page the human directly"** (degrades to today's
behaviour, never worse). **Metering seam + runaway guard** — an alert storm must not fan out into unbounded model
spend; the concrete storm controls are **D9**. A **cost-appropriate model tier** — **Sonnet 4.6** as the triage default (correlation is real reasoning),
**Haiku 4.5** for cheap structuring/classification sub-steps, **Opus 4.8** only on escalation; the eval set (D6), not a
guess, justifies any change. Steady-state spend is trivial (~cents per triage); the cost risk is a runaway alert storm,
which the runaway guard — not the model tier — bounds. Runtime shape (standalone service vs. `Agent` CRD) was the
ADR-074/075 open question; it is now **resolved to the first-class `XAgent` composite** ([ADR-082](082-platform-agent-runtime-xagent.md)) —
a declarative claim provisions the agent's identity/RBAC, ArgoCD delivers the signed workload.

### D9 — Storm control & the unit of triage

An alert storm is the failure mode that turns a helpful agent into an expensive, noisy one — N alerts naively fan out
into N model runs. Control is first-class, and most of it rides Alertmanager config already built (P4 #604):

- **The unit of triage is the Alertmanager *alert-group*, not the individual alert.** A cascading failure that trips
  20 alerts arrives as one grouped notification → one triage, not twenty. **Inhibition** (P4 critical-suppresses-warning)
  and grouping/throttling (`group_wait`/`group_interval`) are Alertmanager-side and come for free.
- **Dedup/coalesce via the cache (D3).** Keyed on the alert-group fingerprint: a re-notification of an already-triaged
  group links the prior card or does a cheap delta, never a fresh triage.
- **Concurrency cap.** A bounded runner pool; excess triages queue (D3), so a burst can't fan out into unbounded
  concurrent model calls or trip Bedrock rate limits.
- **Rolling token/cost budget = the circuit breaker.** On breach the agent **sheds load gracefully** — stops triaging,
  posts a *single* "triage paused — storm in progress, N alerts, paging directly" notice, and falls back to raw alert
  delivery. This is the D8 runaway guard made concrete, wired to the kill-switch.
- **Severity-first under load.** Triage critical groups first; defer/drop info-warning (reuse the P4 severity labels).

Net: Alertmanager absorbs most of the storm; the agent-side additions are cache-dedup, the concurrency cap, and the
budget breaker.

### D10 — Calibrated uncertainty & the human-handoff floor

The dangerous failure isn't silence — it's a **confident-wrong** RCA that sends responders down the wrong path and
*lengthens* the outage. So "I don't know" is a **first-class output**, not a failure:

- **The card carries `confidence` + a `disposition`** ∈ {confident-lead · weak-leads · insufficient-evidence}. Below a
  confidence floor, the agent **defaults to insufficient-evidence**: it surfaces the *raw evidence it gathered* +
  "no strong hypothesis — here's what I looked at; paging a human," instead of fabricating a cause.
- **Never invent a culprit change.** If change-correlation (D2) finds no plausible correlated change, say so — don't
  guess one.
- **The human-handoff is the floor; the confident triage is the value-add.** Even a confident card is a *proposal*
  (D4 propose-only), restated as such. Worst case degrades to today's behaviour: a human paged with the raw alert.
- **The eval rewards calibration (D6), not just correctness** — a correct *abstention* on a hard/novel case scores
  well; a confident-wrong scores **worse than** an abstain. An agent that knows when it doesn't know is worth more than
  one that's right slightly more often but bluffs the rest.

### D11 — Surfaces & feedback capture

The first surface is the **incident channel (Slack)** — already wired in P4 (#610, the `refplat` workspace /
`#platform-alerts`); the triage card threads onto the alert notification. The channel-agnostic core (D1) keeps
PR-comment and Backstage as later adapters.

The **triage card**: summary · ranked hypotheses (each with `confidence` + **evidence as deep links** into
Grafana/Tempo, not prose) · the change-correlation lead (D2) · suggested *next diagnostic step* · disposition (D10).

**Feedback capture is built day one — it cannot be backfilled.** The card carries **accept / correct / dismiss**
buttons; the human's reaction **is** the D6 online eval signal, and it accrues into the production-shadow corpus (D6) —
closing the loop from *real triage → labeled case → regression suite*. Feedback is itself telemetry (the human-decision
span, D7/ADR-076). *(Identity caveat: Slack SAML/SSO is paid-tier; tier-0 attributes feedback by Slack user and ties to
Keycloak identity later.)*

### D12 — Signal coverage (the stated goal, made explicit)

| Signal | How the triage copilot generates it |
|---|---|
| **Traces** | Multi-step agent loop; every obs query / k8s read / GitHub call a child span (GenAI + A2A semconv); async ingest→runner propagation. |
| **Metrics** | RED on every service (free via Beyla); per-call **token + cost + model** + tool-call success/latency; queue depth/lag; cache hit-rate; DB pool. |
| **Logs** | Structured, `trace_id`-correlated reasoning/tool logs under the D5 tiered-capture gate. |
| **Profiles** | Correlation/summarization + the eval-scorer batch = genuinely CPU-variable Pyroscope flame graphs. |
| **Alerts / SLOs** | Real failure modes (model timeout, rate-limit, tool failure, bad-context retry) → meaningful error-budget burn; finally gives **P6 APM / P9 SLOs** live input. |
| **Correlations** | The headline drill end-to-end: alert → trace → tool spans → logs → token-cost metric → profile; plus quality↔cost↔latency from the eval loop. |

## Design grounding (researched 2026)

A deep, adversarially-verified literature pass (Anthropic agent engineering, OWASP LLM01:2025, the prompt-injection
design-patterns paper arXiv 2506.08837, IMDA MGF, CSA Agentic NIST AI RMF Profile, Simon Willison's lethal-trifecta)
**confirmed the major design calls** and added a few sharpeners:

- **Single agent, not multi.** Multi-agent runs ~15× the tokens and is an explicit *poor fit* where agents must share
  context / are interdependent — exactly triage. The single-agent topology (D3) is the evidence-backed choice.
- **Plan-Then-Execute as a security property.** Decide *which* read tools to call **before** ingesting untrusted
  content, so a malicious log line / commit message / k8s field cannot redirect tool calls (control-flow integrity).
  This upgrades the deterministic-context-pack-then-bounded-follow-up loop (D1) from "tidy" to "injection-resistant".
- **The lethal trifecta, and why we're safe.** Triage has *private data* (telemetry) + *untrusted content* (logs are
  attacker-influenceable) but **no exfiltration path** — read-only, no remediation tool in the codebase, output only
  to the incident channel. Breaking the third leg is the whole defense (D4/D5). Guard the output surface so it cannot
  become an exfil channel.
- **Authority in trusted code, never the prompt** (IMDA, almost verbatim): read-only lives in Pod Identity + the tool
  layer; *no write/remediation tool is wired in at all*. "Never remediates" is an IAM/code fact, not an instruction.
- **Behavioral telemetry as an injection canary** (CSA Tier-2): emit action-velocity, permission-escalation-rate,
  cross-boundary-invocation, exception-rate. For a read-only agent these are **~0 by construction**, so any nonzero
  value is a strong tamper/injection signal — a cheap, high-value addition to D7.
- **Governance tier (correction).** Our "on-the-loop" agent maps to **CSA Tier-2 "constrained autonomy"** (document
  the action scope, escalation trigger, approval authority; catalogue the agent identity centrally as a non-human
  identity). *Note:* the four-level "agent proposes / collaborates / operates / observes" spectrum is **not** in the
  IMDA MGF (that attribution was refuted in verification) — cite CSA Tier-2, not an IMDA spectrum.
- **Prompt injection is unsolved by construction** — no published defense is individually reliable; design against it
  as a permanent constraint (the read-only/propose-only posture), not a patchable bug.

## Scope

**In:** the channel-agnostic core + one surface adapter (Slack/incident channel); the ingest/runner/eval-scorer
topology with DB + cache + queue; read-only scoped identity (D4); the D5 read-side data boundary; the **retrospective
incident-replay harness** + online outcome signals + `pass^k` (D6); the ADR-076 GenAI instrumentation wrapper (D7);
signed composite release + kill-switch + runaway guard (D8); storm control on the alert-group unit — dedup, concurrency
cap, budget circuit-breaker (D9); the calibrated-uncertainty output + human-handoff floor (D10); the Slack triage card
with accept/correct/dismiss feedback capture (D11).

**Deferred:** PR-comment / Backstage / additional channel adapters; any *acting* (auto-remediation, runbook execution)
— a separate, higher-tier decision, not in this propose-only agent; the LLM-judge explanation eval; cross-incident
memory / RAG over postmortems; a first-class `Agent` CRD (only if tier-0 shows the shape earns its place); the
Langfuse LLM lens (ADR-076 D4, adopt-when-triggered).

## Success criteria

- **Observability stack exercised end-to-end** — every signal in D12 flowing with real data; **P6 APM, P9 SLOs, and the
  ADR-076 agent-trace model validated live** (the primary goal). The backbone goes from "built, zero input" to
  "ingesting a real, signal-rich workload."
- **Substrate proven** — the **first** agent rides the ADR-074 primitives (identity, gate/human disposition, eval,
  kill-switch, data boundary, metering) without bespoke machinery, **and on the *harder, non-oracle-able* case** — so a
  clean pass is strong evidence the substrate generalizes, not just that it fits an oracle-able claim-authoring agent.
- **Safe** — propose-only verified by the *absence* of any write/exec grant; zero data-boundary violations; regulated
  tiers metadata-only; `pass^k` ≥ the tier-0 threshold.
- **Useful** — retrospective-replay correctness ≥ the agreed bar on the historical set; a positive human
  accept-rate and a non-negative MTTA delta online (qualitative first).

## Dependencies & sequencing

Rides the **live** backbone (ADR-077; #102 P1–P5/P11) and the ADR-076 agent-trace layer; exercises the ADR-074
substrate primitives. **Gated on the first-agent eval-feasibility spike** — fault-injecting known failures in a
walled-off preprod namespace, freezing the telemetry into graded fixtures (D6), and confirming the harness produces a
usable graded signal **before** committing to the full agent (D6 is the risk; de-risk it first). Plan:
`docs/plans/080-triage-copilot-eval-spike.md`. The spike rides the **P10 preprod-spoke work** — the metrics, **logs,
and traces** spokes are **already built (#625)** and the hub receives the `preprod` tenant, so what remains is
**operational**: scale preprod up, **apply + verify** the logs/traces spokes flow to the hub, and enable the eval test
app's namespace for scrape. This is the **first agent built on the substrate**, revising the
ADR-074/075 plan that put the oracle-able resource agent first (see Context). The resource agent (ADR-075) is **not a
prerequisite** — it remains a valuable **complementary, later** build whose deterministic oracle is a cleaner, though
lower-coverage, substrate check.

## Consequences

- The observability stack finally has a real, rich, continuous workload — APM/SLO/correlation phases get exercised with
  live data instead of synthetic load, and gaps surface against something that matters.
- The agentic thread wakes on **concrete demand**, and the substrate's **first** proof is deliberately the *harder*
  no-oracle case — a stronger generalization claim if it passes, but a front-loaded eval risk we take on knowingly.
- We take on the **eval-without-an-oracle** risk explicitly; the retrospective harness contains but does not eliminate
  it, and the honest gap (novel incidents) is documented, not hidden.
- The agent reads cross-tenant operational telemetry — a new content-exposure surface — bounded by the D5 read-side
  data boundary; regulated tiers stay metadata-only.
- A genuinely useful on-call tool ships as a by-product, but its **deliverable is the exercised observability stack +
  the proven substrate**, not a beloved chatbot (the ADR-075 humility applies).

## Alternatives considered

- **A non-agent telemetry workload** (microserviced demo product / FinOps portal) — generates telemetry but doesn't
  advance a roadmap bet, and a generic product emits a narrower, more uniform signal set than an agent's fan-out;
  rejected for *coverage per effort* and strategic alignment.
- **The full IDP / Backstage replacement** — strategically attractive but observability-thin per unit of build effort
  (mostly CRUD over one DB), and self-referential; kept as a north star to harvest into later, not the exercising
  workload.
- **The resource agent (ADR-075) as the first agent** (the original ADR-074/075 plan) — it's oracle-able and
  lower-risk, but bursty/low-volume, so a *weak* observability exercise and not the agent we have demand for; we build
  the triage copilot first and keep the resource agent as a complementary, cleaner-oracle substrate check.
- **An *acting* on-call agent (auto-remediation)** — far higher risk, requires the action/disposition machinery
  ADR-074 has not built, and is unnecessary to exercise the stack; explicitly out of scope — this agent only proposes.
- **A synthetic load generator (k6) to feed the stack** — already have it (observability-k6) and it produces
  *unrealistic* telemetry with no utility and no agent-obs signal; rejected as the "throwaway that does nothing useful."

## Related

[ADR-074](074-agentic-workloads-platform.md) (the substrate — parent) · [ADR-075](075-resource-agent.md) (the
oracle-able, complementary agent — a later, cleaner-eval substrate check) · [ADR-076](076-agent-observability.md) (the agent-trace model this
is the first real producer of) · [ADR-077](077-application-instrumentation-strategy.md) (the now-live instrumentation
on-ramp this rides) · [ADR-043](043-self-hosted-observability-stack.md) + [ADR-044](044-mimir-durable-multi-tenant-metrics.md) + `docs/plans/102-observability-stack.md` (the backbone; P6 APM / P9 SLOs / P13 the workload feeds) ·
[ADR-013](013-compliance-tier-model.md) (tiers drive the D5 read gate) · [ADR-051](051-backstage-developer-portal.md)
(CNPG datastore pattern). Epics: #554 (agentic), #102 (observability).

## Implementation notes (as-built, 2026-06-26)

Built and live on the hub as `XAgent` #1 ([ADR-082](082-platform-agent-runtime-xagent.md)). What shipped beyond the design:

- **The loop (D1/D3):** PLAN → GATHER → REASON → DISPOSE in Go — one structured Bedrock call (Sonnet, validate-and-retry),
  calibrated abstention below the confidence floor. Multi-cluster: the obs `X-Scope-OrgID` tenant follows the alert's
  `cluster` label, and ArgoCD on the hub is the cross-cluster change source — so **cross-cluster k8s auth proved unnecessary**.
- **Playbooks (PLAN), per failure mode:** `SelectPlaybook` routes the alertname to one of **crashloop / oom / not_ready /
  latency / default**, each with its own ordered gather plan + a reasoning *focus* appended to the prompt. The plan is fixed
  before any untrusted content is read (Plan-Then-Execute integrity). The single-playbook slice grew into five.
- **Six grounded tools (D2/D12):** `get_recent_changes` (ReplicaSets/Events + ArgoCD — the change-correlation signal),
  `get_workload_status` (the pod's own restart count / last-terminated reason+exit code / deployment replicas — the first
  thing a human checks, and the only tool that returns signal for a dead pod that served no RED metric), `resource_metrics`
  (memory-vs-limit + restarts — the OOM signal), `query_metrics` (Beyla RED), `query_traces` (Tempo — the slow span),
  `query_logs` (Loki). Each playbook gathers only the tools that carry signal for it.
- **The surface (D11):** a Block-Kit card — severity color bar, plain-English summary, ranked causes each with a one-line
  rationale/evidence, a next step, Grafana deep links, model/trace/cost footer.
- **The feedback loop (D6/D11), closed + verified live:** Accept/Correct/Dismiss record a verdict (`feedback verdict=… → Loki`)
  — the online calibration signal (accept-rate per playbook/disposition, by LogQL). **Learning:** a *private* agent (no inbound,
  ADR-010) can't host a public Slack Request URL, so interactivity is delivered via **Socket Mode** — the agent dials *out* over
  a WebSocket; only an app-level token is needed and the card update rides the interaction's `response_url`. The agent's egress
  CNP (the Composition) was widened to `*.slack.com` for it (ADR-082's egress posture).

**Remaining (deliberately deferred):** the eval harness (fault-injection corpus + grader, D6) still lives in the spike —
wiring it as a CI **regression gate** (forks on model-in-CI: deterministic fixture-replay vs live Bedrock) is the next quality
lever; ADR-076 content-capture (the tiered prompt/response on the trace) is partial (the chat span already carries
model/tokens/provider).
