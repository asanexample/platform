# Learn: The Agentic Platform — orientation

How the platform runs **AI agents** as first-class, *governed* workloads — the machinery to run, bound, and
supervise a non-deterministic worker so the worst it can do is waste a proposal, and how it earns more trust
only by proving itself. This is the platform's most distinctive — and most deliberately cautious — area.

**Audience:** platform engineers, and anyone wondering how you let an LLM near production without losing
sleep. **Before you start:** the [Environment API](../environment-api/orientation.md) (the `XAgent` is its
sibling), [Identity & access](../identity/orientation.md) (an agent is a *subject* in the same model),
[Observability](../observability/orientation.md) (agents are observed there — we won't re-teach it), and
[Supply chain](../supply-chain/orientation.md) (an agent's image is signed like any other) all help.

## The question

You want an AI agent to help operate the platform — say, to triage a 3 a.m. alert. But an agent is not a
normal service: it's **non-deterministic**, it's **driven by a model you don't fully control**, it reads
**untrusted input** (alerts, logs, diffs — a prompt-injection surface), and the published defenses against
that are all individually bypassable. There's a real incident on record of an autonomous coding agent
deleting a production database during a change freeze. So:

**How do you let an agent operate your platform — with real access to real systems — such that a
compromised, confused, or hijacked agent *cannot* cause harm? And how does it earn more responsibility over
time without you just hoping it behaves?**

## The one idea: treat the agent like a powerful contractor you don't fully trust

Here's the whole module in a sentence:

> **The platform runs an agent the same way a careful org onboards a powerful contractor it doesn't yet
> trust: through the *same governed front door* as any workload (a declarative claim + the same signed supply
> chain), issued a *tightly scoped badge* (least-privilege identity), allowed only to **propose, never act**,
> **supervised** by a human on anything consequential, **instantly revocable** (a kill-switch), and able to
> **earn more autonomy only by proving itself** on an evaluation track record. Safety comes from *bounding
> capability in advance* — never from trusting the model's behavior.**

Two load-bearing consequences, because they run through everything:

- **Safety is a property of the *bounds*, not the *model*.** You can't reason with an agent, appeal to its
  judgment, or trust a prompt to constrain it. So every control is a *hard* bound outside the model: what
  identity it holds, what IAM it has, what network it can reach, whether it can act at all. A perfectly
  hijacked agent still can't exceed its badge.
- **This is not a greenfield agent platform.** An agent is a *workload with extra demands*, and the platform
  already runs governed workloads well — scoped identity (Pod Identity), admission policy (Kyverno), signed
  supply chain (cosign/SLSA), zero-trust networking (Cilium), and a propose-via-PR gate. The agentic platform
  **extends that existing moat** rather than inventing a parallel one ([ADR-074](../../adrs/074-agentic-workloads-platform.md)).

> **The metaphor for the whole doc: hiring and supervising a brilliant, fast, but *unpredictable* new
> contractor.** You onboard them through HR like anyone else (the `XAgent` claim + the same supply chain).
> You issue a badge that opens only a few doors (scoped identity). For now they may *read* the building and
> *write memos*, but they cannot touch production — every real action goes to a supervisor (propose-only +
> human-in-the-loop). There's a big red button that revokes the badge instantly (the kill-switch). And they
> earn access to more doors *one at a time*, only by a track record that clears a bar (the autonomy ladder).
> **Where it breaks:** a real contractor has judgment and can be trusted to improvise a little; this one
> cannot — its improvisation is exactly the risk — so the bounds are tighter and never rely on goodwill.

Now the tour: what an agent *is* here, how it's *bounded*, how it might *earn* more, and the one real agent
that exercises all of it.

---

## Stop 1 — what an agent is: an `XAgent` (a governed claim)

An agent is defined by **one git-committed claim** — an `XAgent` ([ADR-082](../../adrs/082-platform-agent-runtime-xagent.md)),
and the key insight is that **`XAgent` is to a platform agent what `XEnvironment` is to a tenant**. Both are
Crossplane composites; both turn a single declarative claim into a provisioned *slot* — a namespace, a
ServiceAccount, an identity, RBAC, and network policy — reconciled from git; both split *provisioning*
(Crossplane) from *workload delivery* (ArgoCD). The difference is what they're shaped for: `XEnvironment` is
tenant-shaped (quotas, stages, domains); `XAgent` is **agent-shaped and deliberately lean** — a model, a
read scope, bounded autonomy, and a kill-switch.

> *If an `XEnvironment` provisions an apartment for a tenant to move into, an `XAgent` provisions a **guard
> booth** on the hub: a small, locked-down slot with read-only windows into the building and exactly one
> phone line out — to the model.*

A claim declares intent — team/product, the (pinned) model, whether it may read observability, any extra IAM,
its autonomy mode, and its lifecycle phase — and the Composition renders the slot. Agents run on the
**platform hub** (not a tenant cluster), because that's where the signals they read already live. Adding an
agent is a **git commit** — no per-agent infrastructure apply. The [runtime deep dive](deep-dive-the-xagent-runtime.md)
walks the whole claim → slot mechanism and the GitOps control plane.

---

## Stop 2 — how it's bounded: identity, least privilege, and the kill-switch

This is where "safety is a property of the bounds" becomes concrete. An agent is a **governed principal**, and
the platform boxes it in on four independent axes ([deep dive](deep-dive-bounding-the-agent.md)):

- **Identity — a scoped badge, not a master key.** The agent gets a named ServiceAccount and **EKS Pod
  Identity** (keyless AWS creds, no keys in the image). Its IAM is *exactly* a Bedrock **invoke** grant (call
  the model — never manage Bedrock) plus any extra statements, which are **deny-set validated** (no `iam`/`sts`/`organizations`/`account` *actions*, no wildcard action) just like a
  tenant's. Its only in-cluster power is **read** — a fixed, read-only
  `platform-trust-observability-reader` ClusterRole that pointedly **excludes Secrets**. There is **no write, exec, or
  remediation verb anywhere in its grant.**
- **Propose-only, by *absence of capability*.** The agent's single write action is *posting a message* (a
  proposal to a human). It literally lacks the permissions to do anything else — "propose, don't act" isn't a
  prompt instruction it might ignore, it's an IAM fact. The worst case of a fully hijacked agent is *an
  ignored Slack message*.
- **Network default-deny, both directions.** Egress is locked to just what it needs — the model (Bedrock),
  the incident channel (Slack), read-only GitHub, and the in-cluster observability stack — and *nothing* else,
  so it can't exfiltrate or phone home.
- **The kill-switch.** Flip `lifecycle.phase: suspended` and commit; the Composition **removes the agent's
  Pod Identity binding** → no model access → *it can't reason.* It's a hard stop that bites at a layer GitOps
  can't heal around (you can't just `kubectl scale 0` — the delivery controller would revert that). *A
  dead-man's switch: it doesn't ask the agent to stop, it removes the fuel.*

Add the **data boundary** ([ADR-076](../../adrs/076-agent-observability.md)): the agent's telemetry carries
*metadata* freely (tokens, latency, tool names), but raw prompt/response content is redacted per compliance
tier and **never** shipped to a SaaS; secrets in context is a hard *never*. All of this — plus admission
policy (Kyverno) and an admin-gated authoring flow — is genuinely **built and enforced** today.

---

## Stop 3 — how it earns more: the autonomy ladder (designed, not built)

Propose-only is the *floor*, not the forever. The question the platform answers *on paper* — and this is the
honest part — is how an agent could safely earn the right to *act* on some things without a human each time
([ADR-086](../../adrs/086-autonomous-agent-access.md), **still a Proposed sketch**).

The design: autonomy is **graduated, per-action-class, earned, and machine-bounded — never a global property
of an agent.** An agent earns autonomy on *one action class at a time*: it runs in **shadow** (proposes, and
the system records what it *would* have done and whether that was right) → an **evaluation** service scores
its track record against a per-tier bar → it's **promoted** to act autonomously on that class → and
**auto-demoted on regression**. Irreversible or unbounded action classes are classified *never*-autonomous. The
reframe: *"more permissive" must not mean "fewer guardrails"* — it means moving the guardrail from a
human-in-the-loop to a *machine-enforced* bound.

> *It's a graduated driver's license.* A new driver earns privileges per skill — learner's permit (supervised)
> → provisional (measured) → full license — and a violation *demotes* them.

**The honest status: almost none of this is built.** The `autonomy.mode` field is **schema-locked to
`propose-only`** — the API can't even *express* autonomy today. The grader, the reversibility registry, and
the action-time policy engine are all unbuilt; the whole thing is gated on an **eval-as-a-service** that
doesn't exist yet. **The one shipped piece** is the *forward-capture substrate* (#1074): a hardened,
write-once S3 corpus that captures real triage episodes *now* — because telemetry ages out, so an incident
you don't record at the time is lost forever, and you can't build an eval corpus retroactively. *It's a
flight-data recorder installed before the plane is ever certified for autopilot: you run the black box on
every human-flown flight now, so that someday you can prove the autopilot would have flown each one.* Build
the pipeline; the examiner doesn't exist yet. The [autonomy deep dive](deep-dive-autonomy-and-evaluation.md)
is careful about exactly this line.

---

## Stop 4 — the one real agent: the triage copilot

All of the above is exercised by **exactly one live agent**: the **triage copilot**
([ADR-080](../../adrs/080-triage-copilot.md)), the reference `XAgent`
([worked-example deep dive](deep-dive-the-triage-copilot.md)). Its job in one line: *shorten the time from
"an alert fired" to "a human knows where to look and who owns it."*

The loop: an **Alertmanager webhook** triggers it (no human kicks it off — it's *autonomously triggered*),
it scopes the blast radius, gathers **read-only** evidence (metrics, logs, traces, pod state), does the
highest-yield move — **change-correlation** (find the PR whose rollout window straddles the alert and join the
failure signature to the diff) — ranks hypotheses with evidence deep-links, **resolves the owner**, and posts
a **triage card** to Slack with a confidence-calibrated *disposition*. Below a confidence floor it *abstains*
and pages a human rather than fabricating a cause (a confident-wrong root cause is the dangerous failure).

Two threads connect out to other modules:

- **Owner-routing** ([ADR-084](../../adrs/084-platform-identity-directory-and-owner-resolution.md)): the agent
  resolves the culprit's **team** from the git registries (it's a *consumer*, not a control plane) and posts to
  that team's Slack — the live **team floor**. Resolution is split from mention-policy so a directory bug can't
  misfire a page; the finer path (@mentioning the commit *author*, live on-call paging) is designed but **not
  yet built** (ADR-084 Phases 1/3).
- **Evaluation**: the triage card carries **accept / correct / dismiss** buttons; the human's verdict *is* the
  online eval signal (and the seed of the future autonomy ladder).

It's **autonomously *triggered*, but strictly propose-only in *action*** — the single most important
distinction in this whole module. It's observed like any workload (the "Triage Agent" dashboard,
[Observability](../observability/deep-dive-agent-observability.md)).

---

## The honest status — one agent, mostly early

Because this portal refuses to oversell, and this domain is the easiest to oversell: **there is exactly one
agent and one `XAgent` claim.** What's genuinely **built and live**: the `XAgent` runtime (the XRD +
Composition on the hub), the triage copilot on it, agent observability, and all the *bounding* machinery
(least-priv identity, the envelope, the kill-switch, admission policy, the data boundary). What's **designed
but not built**: the **autonomy ladder** (only its capture substrate ships; `autonomy.mode` is locked to
propose-only), the **resource agent** (ADR-075, a second designed-but-unbuilt agent), and **eval-as-a-service**
(the hard blocker for any autonomy). What's **deferred**: multi-agent / agent-to-agent, full content-capture,
and a model gateway. The product here is *the governed substrate to run many agents safely* — and today it's
proven by running exactly one, at the safest possible setting.

## When it breaks — the ones you'll actually hit

- **"The agent didn't do anything / just posted a message."** That's the design — it's **propose-only**. It
  reads and proposes; a human acts. If you expected it to remediate, it can't (no write capability).
- **"I need to stop the agent *now*."** Set `lifecycle.phase: suspended` and commit — it drops the Pod
  Identity and can't reach the model. Don't `kubectl scale` it (GitOps will revert that).
- **"Why can't I set `autonomy.mode: autonomous`?"** The field is schema-locked to `propose-only` — autonomy
  isn't built. That's not a bug; it's the safety floor until eval-as-a-service exists.
- **"The agent can't reach Bedrock / obs after I deployed it."** RBAC ≠ reachability — a hub agent needs
  explicit *network* wiring (a Cilium egress policy for the model + a NetworkPolicy admitting the trigger); a
  read grant doesn't open the network path.

## Recap — say it back

Cold: *how does the platform run an AI agent safely?* If you can say —

> "Like a **contractor it doesn't trust**: an **`XAgent`** claim (sibling of `XEnvironment`) → a locked-down
> hub **slot**, through the same signed supply chain. Safety is in the **bounds, not the model** — a scoped
> **Pod Identity** (Bedrock-invoke + read-only, **no Secrets**, no write/exec), default-deny network,
> **propose-only by absence of capability**, a **kill-switch** that drops its model access, and admission
> policy — all **built**. It could earn more via a **graduated, eval-gated autonomy ladder** (ADR-086) — but
> that's **designed only**; `autonomy.mode` is locked to propose-only and only the eval *capture substrate*
> ships. The one live agent is the **triage copilot**: autonomously *triggered* by an alert, it gathers
> read-only evidence, correlates the culprit change, routes to the **owning team** (ADR-084), and **proposes**
> a triage card — a human acts. One agent, safest setting; the substrate to run many is the point" —

— then you hold the whole agentic platform, and "let an LLM operate production" stops being reckless.

## Go deeper

- [The XAgent runtime](deep-dive-the-xagent-runtime.md) — the claim → slot Composition, the `XEnvironment`
  parallel, the GitOps control plane, Bedrock, and the lifecycle.
- [Bounding the agent: identity & safety](deep-dive-bounding-the-agent.md) — the scoped Pod Identity, the
  envelope, least privilege, the network lock, the data boundary, the kill-switch, and the admission gates.
- [Autonomy & evaluation](deep-dive-autonomy-and-evaluation.md) — the graduated autonomy ladder (designed),
  the eval loop, and the forward-capture substrate that's actually built.
- [The triage copilot](deep-dive-the-triage-copilot.md) — the one live agent, end to end, plus owner-routing.
- The lookup: the [Reference](reference.md). Cross-links: [Identity](../identity/orientation.md),
  [Observability](../observability/deep-dive-agent-observability.md), [Environment API](../environment-api/orientation.md).
