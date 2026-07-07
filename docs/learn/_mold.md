# The teaching-module mold

> Meta-doc, not a lesson. This is the template every `docs/learn/<subsystem>/` module is authored
> against, so the portal reads as one voice and future modules don't drift. If you're here to learn,
> go to [the portal hub](README.md).

## Why this exists

The rest of the platform's docs (ADRs, runbooks, architecture) **explain** — they inform a reader who
already holds the mental model. They don't **teach** — build that model in someone who lacks it. This
portal is the teaching layer. The mold below is what makes a doc teach instead of explain.

## The verification gate — every claim, or it doesn't ship

**This is the first rule, and it overrides convenience.** Documentation is a **trust artifact**: a reader who
finds *one* wrong claim stops trusting *all* of it — and stops trusting the platform. A plausible-sounding
sentence that turns out to be false does more damage than a gap. So:

> **Every factual claim, instruction, and example must be verified against a *primary source* before it
> ships. If you can't verify it, you don't write it** — you verify it, mark it explicitly as
> *designed-not-built* / *unverified*, or omit it. Never assert from plausibility, inference, memory, or "it
> obviously works this way."

- **Primary source = the code *and* the live environment.** The module source, the CRD/XRD schema, the
  Composition, the Terragrunt unit, the workflow YAML, the scaffolder template — *and* the running truth:
  `kubectl` on the cluster, `gh` on GitHub, the `aws` CLI, `cosign` on a real image. Read the thing that is
  actually true.
- **Secondary sources are leads, not proof.** ADRs, CLAUDE.md/AGENTS.md, runbooks, memory, and *this portal's
  own other docs* may be stale or aspirational. They tell you where to look; they never substitute for
  looking. (Verified counter-examples this rule was written from: a doc said "not built" when all four engines
  were live; an ADR comment said "Phase A: S3 only" when SQS/SNS/Dynamo shipped; a `spec.validationFailureAction`
  field read `Audit` while enforcement was real.)
- **Behavioral claims about flows are the trap.** "Onboarding creates the repo," "the scaffolder wires CI,"
  "this field drives that policy," "X is enforced" — these *feel* knowable from the mental model and are the
  ones most often wrong. Trace each to the actual code path or run it. (This rule exists because "you bring
  the repo" shipped — the scaffolder *creates* it.)
- **Examples and commands must be run**, with output confirmed to match (don't hardcode drifting values —
  ages, hashes). Numbers, names, ARNs, digests: copied from real output, redacted per the secret rules, never
  invented.
- **The ship checklist:** before opening the PR, walk the doc and for *every* claim ask "what did I verify
  this against?" If the answer is "it seemed right," stop and verify or cut it. A doc is done when every
  sentence has a source behind it, not when it reads well.

This gate applies to **all** tiers — orientation, reference, how-to, cheatsheet, everything — and to edits,
not just new docs. Same rule the platform applies to its own controls (verify intent-vs-effected): "it's
written down" is a claim to confirm, not assume.

## The split

Each subsystem is **two public documents** plus, for the core subsystems, **two private aids**.

| Artifact | Home | Job |
| --- | --- | --- |
| `orientation.md` | public (repo) | The teaching **journey**. One continuous, spoken-style read. |
| `reference.md` | public (repo) | **Look-up**: full mechanism, glossary, gotchas, external links. |
| `cheatsheet.md` | public (repo), **optional** | The commands to *interact with* the module's concepts — a run-verified quick reference (lookup). |
| `troubleshooting.md` | public (repo), **optional** | A **symptom → cause → fix** index for failure-prone *mechanism* modules; links runbooks for the operational fix, doesn't duplicate them. |
| `deep-dive-<topic>.md` | public (repo), **optional** | Teaching-voiced **depth on one hard mechanism**, for a reader past the Orientation. |
| `tutorial-<topic>.md` | public (repo), **optional** | Learning-by-**doing**: a beginner follows guided steps and it works. |
| talk-track | **private** (Obsidian) | 60s / 5min / deep **spoken** narratives — recall + rehearsal. |
| interview Q&A | **private** (Obsidian) | "When they ask X, say Y." Personal framing. |

**Public/private boundary:** the teaching docs are public — they're part of the demo. Anything that is
*the author speaking as themselves* (talk-track, interview Q&A) is private and lives in Obsidian, never
the repo. A demo-video voiceover derives from the public `orientation.md`, so keeping the talk-track
private costs the public nothing.

**Don't feel obligated to all the tiers.** Only `orientation.md` + `reference.md` are the baseline (plus a
link to the portal glossary). Everything else — deep dive, tutorial, cheatsheet, troubleshooting — is
**optional and build-on-demand**, added only where a subsystem *earns* it (a mechanism with real internal
depth, a safe hands-on path, a rich command set, a failure corpus). A typical module is two files, not
seven.

**Granularity — split by mental models, not topic size.** A domain becomes N modules by *how many distinct
"one ideas" it holds*, not how big it looks. Observability splits many ways — each signal, the collection
pipeline, SLOs, multi-tenancy: each its own model — while "CI & runners" folds into supply-chain (one thin
model). Granularity is also **fractal**: a rich sub-topic can be its own *module* **or** a *deep dive*
inside one — decide per build. And **don't pre-decompose a domain to its finest grain in the plan**: for a
big or late-sequence domain, capture the *axes* it decomposes along + a **first cut**, and let the leaf
modules crystallize when you actually build it. Finer splits pinned now are false precision — they'll move.
Some domains (observability) are large enough to be **sub-curricula** with their own internal structure.

**When to *stop* decomposing.** The signal you've gone too far: a split that *fragments one idea* — the
reader must hold two files to grasp a single model. Optimal grain is **discovered at build, not in the
plan** — a module is right-sized when its Orientation carries one mental model without overload and without
splitting a single idea, which you learn by *writing it and testing comprehension*, not by subdividing a
table. The plan's job ends at *axes + first cut*; over-refining it past that is procrastination on the real
test (building one and seeing if it holds).

## `orientation.md` — the section spec

Write it as **one continuous document**. Do **not** fragment the journey into many small pages —
momentum is what makes teaching stick. The arc, in order:

1. **Reader baseline** — one line stating the assumed starting knowledge. This is the floor "teach it
   high-level" starts from; without it, "high-level" has no meaning.
2. **Hook + purpose** — goal-first, no jargon: the problem this subsystem solves *for a human*, then its
   **purpose** — why it's worth building *at all* (what breaks without it; why it matters at scale).
   Motivation is a comprehension lever: a reader who knows *why to care* learns the *how* better. Keep
   this distinct from **design rationale** (why these specific choices were made) — that belongs in
   `reference.md`'s gotchas, not here. Where a subsystem's purpose is an instance of the *platform's*,
   gesture up to the portal-level "why" and log the crosslink.
3. **The one mental model** — a single sentence **plus a diagram** (mermaid). The one idea the reader
   should leave with.
4. **One worked example, traced end-to-end** — the spine. Follow **one real object** all the way, with
   **real captured output** (never invented) and a flow diagram. This section is where a module lives or
   dies.
5. **Vocabulary — just in time.** Introduce each term at its moment of first need, in context. **Never**
   a glossary dump up front (a term defined before the reader has a model to hang it on doesn't stick —
   that's the exact failure this portal exists to fix).
6. **The substrate — high level, inline.** If the module sits on an unfamiliar technology (Crossplane,
   Cilium, …), teach *enough of it inline* to carry the reader through how **we** use it. Bring them
   along; don't send them away to go become experts elsewhere.
7. **Show it break — and recover.** Don't only trace the happy path. Show a real *failure* state and how
   to read it (the status conditions, where the cause lives), then the *self-heal*. Watching the loop fail
   and right itself teaches the model deeper than any success trace — and it's what an operator needs.
8. **Make the reader *do* one thing.** End the passive stretch with an active step: run it, change one
   input, predict the diff (a "completion problem"). Doing beats watching for retention and transfer.
   Offline (`render`-style, no cluster) is ideal.
9. **Bust the predictable misconceptions** — "you might think X → actually Y", for the wrong models
   readers reliably form. Correcting a *named* misconception sticks harder than only stating the truth.
10. **One-glance recap** — the whole thing on one screen (what you write · the players · the behavior ·
    what you get · the one command). Aids consolidation and revisiting; doubles as the interview cheat-sheet.
11. **Explain-it-back** — a consolidating recall check at the very end ("close this doc and answer…"), and
    the seed for the private talk-track.

### Interleave the recall checks — don't save them all for the end

Drop a one-line **Quick check** after each major beat (after the mental model, after the worked example,
before the substrate), not just one block at the end. Retrieval practice has a *forward effect*: a quick
recall doesn't only cement the section just read — it measurably improves how well the reader absorbs the
*next* one. Near-zero effort, compounding gain; treat this as the **single highest-leverage move in the
mold** (Pastötter & Bäuml 2014; Chan, Meissner & Davis 2018).

### Serve the expert too — the expertise-reversal effect

The step-by-step that on-ramps a novice becomes *noise* to a reader who already holds the model: the same
guidance that helps novices **hinders** experts by adding redundant load (Kalyuga et al. 2003). So give
the expert an escape hatch — one page, two paths:

- a **skip link** at the top of the Orientation ("Already fluent in X? → the Reference is the terse
  lookup");
- the **Reference leads with the terse facts** experts (and the author's interview-prep pass) actually
  want — schema table, commands, gotchas — never narrative.

### Metaphors — for the hard concepts

For each module's genuinely hard or novel ideas, reach for a **load-bearing everyday metaphor** — the
"explain it like I'm five" move. It's how intuition actually forms. Rules:

- **Attach the *primary* metaphor to the module's single most novel concept — the "one idea" — not to
  its cast of parts.** The hardest, most surprising thing is what needs the strongest handhold; naming
  the components is secondary. In the env-api module the headline is *continuous reconciliation* → the
  **thermostat** (the verb); the **restaurant**, which merely names XRD/claim/Composition, is the
  supporting cast (the nouns). The observability module's headline metaphor should be about *signals
  flowing*, not about naming Loki/Mimir/Tempo.
- **Pick one or two that carry weight; don't sprinkle.** A metaphor per paragraph is mush; one strong
  metaphor per hard concept is a handhold.
- **Choose metaphors that need no prior knowledge.** Explaining a control loop by analogy to "Kubernetes
  replicas" only works for people who already know Kubernetes — that's not teaching, that's assuming. A
  *thermostat* needs nothing. (The env-api module uses a **thermostat** for reconciliation and a
  **restaurant** — menu / order ticket / kitchen — for XRD / claim / Composition.)
- **Say what the metaphor shares AND what it does *not*.** Every analogy necessarily breaks down — a
  mapping that held everywhere would just *be* the thing — and an *unexplained* analogy actively seeds
  misconceptions, not merely fuzzy ones. So name the shared relation *and* demonstrate the un-shared one
  explicitly. This is a required, first-class part of every metaphor, not optional polish (Advances in
  Physiology Education 2010; Gentner structure-mapping).
- **Metaphors live in the *teaching* tiers** — `orientation.md` **and** any `deep-dive-*.md` — not
  `reference.md` (precision). In a deep dive, prefer **callbacks to the orientation's established metaphors**
  (env-api's thermostat / recipe) over new ones: continuity reinforces, and a fresh metaphor mid-deep-dive
  risks the sprinkle. Introduce a *new* one only for a gotcha the callbacks don't cover.

## `reference.md` — contents

Look-up, not a narrative. Full mechanism; a proper **glossary**; **gotchas that teach** (the
"we chose X not Y because Z would break" gems — the highest-value teaching per line); and **external
substrate links**.

External links rules:

- **Annotate** each: what it is · why it's worth it · how long.
- **Quality bar** — official docs / maintainer / CNCF / genuinely authoritative. No random blog posts.
- **Version-tag** — flag anything that predates our version, because it will actively mislead
  (e.g. we run Crossplane **v2** cluster-scoped XRs; v1 "claim" tutorials teach a wrong model here).
- **Optional depth, never a prerequisite** — the module must be followable without leaving the page.
- **No hard cap** — each link earns its place; in practice that's few. Prefer stable canonical landing
  pages over deep anchors (they rot slower).

## Deep dives — the optional third tier

Orientation builds the model; Reference is the lookup. A **deep dive** is the missing middle: a
teaching-voiced, guided explanation of **one hard mechanism** the Orientation deliberately abstracted, for
a reader who has the model and now wants to understand a specific piece *properly*. (Diátaxis's
"explanation" quadrant, at depth.) It is **not** the terse Reference and **not** the raw arch-doc/ADR —
those stay the source-of-truth footnotes.

- **Optional, and only for genuinely hard sub-topics.** Most modules need none. A *mechanism* module (real
  internal machinery — the Environment API's Composition, say) earns several; a *conceptual* module (the
  domain model) usually one or none. Build them **on demand, not speculatively** — same discipline as the
  modules themselves.
- **One topic per file** — `deep-dive-<topic>.md`, assuming the Orientation (link back to it; don't
  re-motivate the whole subsystem).
- **Only the deep dives this subsystem *owns*.** A topic that really belongs to another module (access →
  identity, promotion → delivery) is *that* module's deep dive — log the crosslink, don't annex it.
- Same discipline as everything else: teaching voice, **real captured output**, verified commands,
  jargon-grounded, canonical links.

## Tutorials — the learning-by-doing tier

The Orientation and Deep dive are *explanation* (understand); a **tutorial** is the *doing* quadrant — a
beginner follows guided steps, builds a throwaway thing, and it **works**. Distinct from a deep dive
(explanation) and from a **runbook** (how-to: accomplish a real task, for the competent). Same steps as a
runbook sometimes, opposite intent: the tutorial's goal is *the reader learning*, the artifact is
disposable.

- **Guaranteed success, controlled inputs.** A tutorial that can fail isn't a tutorial. Every step is
  verified to work (run it, per the command rule) and produces a predictable result.
- **Structure:** prerequisites → numbered *do-this* steps (each with what you'll see) → "what you did" →
  "next." Predict-then-check beats bare instructions.
- **Needs a safe hands-on surface.** This is real, gated infra — beginners can't freely provision. Today
  the safe surface is **offline `crossplane render`** (no cluster/access); a live **learning sandbox** is
  on the roadmap.
- **⚠️ Provisional-caveat rule.** If the full hands-on path isn't available yet, the tutorial **must say so
  up front** — a prominent banner that the live steps are *provisional / preview* until the sandbox lands,
  what works offline *today*, and which steps light up later. Never instruct a reader to do something they
  can't yet.
- **Optional, built on demand** where a safe path exists — same discipline as deep dives.

## How-to / extending — the platform-engineer contribution tier

The Orientation teaches how a subsystem *works*; but **extending** it — adding a resource engine, a policy,
an environment feature, a front door — is a recurring, high-value platform-engineer job the portal must
teach too. Using a capability is easy; *adding* one is the harder, more valuable skill, and it's usually
undocumented tribal knowledge. That's the **how-to** quadrant (Diátaxis): task-oriented, for a *competent*
engineer accomplishing a real change — not a beginner learning (that's the tutorial), not understanding a
mechanism (that's a deep dive).

- **Where extending is a common activity, the module owns a `how-to-<task>.md` / `extending-<task>.md`.**
  Ask: "will a platform engineer routinely *add to* this subsystem?" If yes (resources → add an engine;
  policy → add a policy; products → onboard a new kind), it earns a how-to. A fixed subsystem doesn't.
- **A thorough, newcomer-followable *playbook* — not a terse recipe.** Assume the reader may never have used
  the underlying tech. Open with a short "new to this stack?" orientation that names each technology in a
  sentence and links where to learn it, then walk **numbered steps**, each naming the **real file**, showing
  **concrete copy-pasteable code**, and carrying **one running worked example end-to-end** (add one real
  thing, start to finish). Length is fine; a playbook someone can actually follow beats a memo an expert can
  skim.
- **Link generously to external docs.** A newcomer should be able to click any unfamiliar concept through to
  its authoritative source (the tool's docs, the provider/API schema, the cloud service). Every link
  curl-verified (link-rot rule); annotate what each teaches.
- **AI-forward.** Most engineers now work *with* coding agents, so a how-to must serve them too: include a
  **"doing this with an agent"** section — a ready-to-use prompt, the exact context/files to attach, the
  **security invariants written as explicit agent guardrails**, and a **review checklist** (the agent does
  the typing; the human owns correctness). Write the whole doc to double as agent context: explicit paths,
  copy-pasteable code, unambiguous verification gates. The task an agent is *worst* at (here: knowing which
  schema fields are real, what must never be user-controlled) is the thing to make loudest.
- **The gotchas are the point.** The highest-value part is *"what bit us adding the last one"* — the
  failures a fresh reading of the code won't reveal (provider-schema quirks, ordering traps, silent
  no-applies). Include them, plus a **verification** path (offline → apply → e2e) and the **quality bar**
  when the change touches security / the control plane.
- **Grounded in a real prior extension.** The recipe is trustworthy because it's how the *existing*
  instances were actually built (e.g. S3 → SQS → SNS → DynamoDB), gotchas and all — not a guess at the steps.
- **Optional, built on demand** — but bias *toward* building it: "how do I add a capability here?" is one of
  the most common real platform-engineer questions, and its answer is the moat this portal exists to capture.

## Screenshots / UI visuals

Where the *system's own view* teaches (a portal/UI), include it. **Automate capture if the target is
reachable**; most platform UIs are Tailscale-only + SSO and are *not* reachable from tooling, so the
fallback is a **visible placeholder** + a capture spec in the module's `_screenshots.md`:

- At the insertion point, a blockquote so nothing renders broken:
  `> 📸 **Screenshot:** <one-line what it shows> — spec in [_screenshots.md](_screenshots.md).`
- `_screenshots.md` lists, per shot: **app · exact URL · nav path · what to frame**.
- Capture → drop the PNG in `images/` → swap the blockquote for `![alt](images/<name>.png)`.
- **Terminal output is a code block, not a screenshot** — greppable and it doesn't rot.

## Video (script-first, when built)

Because the Orientation is written script-first, it maps to video directly — but follow the tested rules
(Brame 2016; Guo et al. 2014; Szpunar et al. 2013):

- **Sub-6-minute segments**, and make the segment boundaries the **interleaved recall checks** — pose the
  Quick check as an interpolated question between segments (proven to cut mind-wandering and lift recall).
- **Narrate over the real captured output** (the `kubectl` / claim→resources trace), not a talking head.
- **Signal** the key line on screen (a highlight or callout); **weed** decorative visuals and background
  music.
- Treat ~6 min as a strong default, not a law — the figure is MOOC watch-time engagement, not a measured
  learning outcome.

## Link to the real code

When a module names a concrete artifact — a Composition, an XRD, a claim file, a Terragrunt unit — link
it. Seeing the actual source is half of why a technical reader trusts (and learns from) the doc. Rules:

- **File-level, never line-anchored.** `composition.yaml` survives edits; `composition.yaml#L214` rots
  the next time someone touches the file.
- **Source links are absolute GitHub URLs** (`https://github.com/asanexample/platform/blob/main/<path>`).
  They point at `main` and, crucially, they still resolve once the portal moves to Backstage TechDocs —
  which publishes only `docs/`, so a relative link into `infra/`/`gitops/` would 404 there.
- **Doc-to-doc links stay relative** (ADRs, runbooks, other learn modules — those live in the published
  tree).
- **Concentrate them in `reference.md`** (its whole job is look-up), plus a *few* high-value anchors in
  `orientation.md` (the claim file; one "see the code" aside for the core machine). Don't shred the
  teaching narrative with links.
- **Link substrate primitives *and tools* to their canonical docs, inline, at first use.** Whenever you
  name something the platform is *built on* — a Kubernetes primitive (namespace, pod, RBAC, admission,
  custom resource) or a substrate tool/service (Crossplane, Kyverno, Cilium, Envoy, ArgoCD, and cloud
  services like ECR / IAM / EKS Pod Identity) — make the term itself a link to its official doc so a
  curious reader can drop one level down without leaving the flow. Once per doc, at first mention; **verify
  the URL resolves** (`curl -sL -o /dev/null -w '%{http_code}'`) — dead external links are the failure
  mode, and prefer stable canonical landing pages over deep anchors.

## Crosslink — weave the portal together

Heavy crosslinking is a hallmark of great documentation, but a module can only link to targets that
**exist** — and the portal is built one subsystem at a time, so most links have to be added *later*.
Treat crosslinking as an ongoing, bidirectional discipline, not a one-shot:

- **When you add a module, run the crosslink pass:** grep every existing `docs/learn/**` for mentions of
  your subsystem (and its aliases), turn them into links to your new module, and link *out* from your
  module to any subsystem that already has one. This is part of "done."
- **Record forward-references you can't yet satisfy** — a subsystem you mention that has no module yet —
  in [`_crosslinks.md`](_crosslinks.md), and clear rows there as you satisfy them. Never invent a link to
  a page that doesn't exist.
- Until a learn module exists for a mentioned subsystem, link to its **architecture doc / ADR** where it
  genuinely helps the reader.
- **In the teaching flow, link to other *learning* modules — not to architecture docs or ADRs.** Those
  are agent-generated *reference / source-of-truth*, a different layer; sending a learner mid-journey into
  one is a category error. Reserve arch-doc / ADR links for the explicit **"go deeper / source of truth"**
  section at the foot of a module. If the teaching-flow target doesn't exist as a learning module yet,
  that's a signal to build it (or log it) — not to link the reference doc inline.

## Every command must run — verify before it ships

A documented command that doesn't produce the documented output is worse than no command: it quietly
destroys trust in the whole doc. So, without exception:

- **Run every command example yourself** against the real system, and **paste only output you actually
  captured** — never hand-write or guess output. (This is the same rule as "real captured output" in the
  worked example, applied to *every* command anywhere in the module.)
- **Re-verify on edits.** If you change a command, re-run it — a "small tweak" is how a working example
  rots. Confirm paths, filenames, and flags actually exist (a plausible-looking path is often wrong).
- **Don't hardcode values that drift.** Ages (`16d`), random name suffixes (`-1f665db7ae69`), timestamps —
  elide them (`…`) or use a placeholder, so the example doesn't become a lie next week. `AGE`-style
  columns are understood as point-in-time snapshots; identifiers a reader must substitute get an explicit
  placeholder (`<your-env>`).
- **Destructive or environment-specific commands** (a `delete`, anything against a shared cluster) are
  shown as clearly-templated instructions (`<your-cluster>`), never as run-this-here examples.
- **A `cheatsheet.md` is the strictest case** — it's *entirely* commands, a reference-family lookup of how
  to interact with the module's concepts (inspect, debug, verify). Every line run-verified, with **access
  notes** (which context/profile/tool each needs), and **secrets redacted** — account IDs, ARNs carrying
  account numbers, and anything SOPS-encrypted in the repo become placeholders (`<platform-acct>`), never
  plaintext, even in real captured output.
- **Don't assume tooling.** Not every reader has every CLI — name the dependency and give a baseline
  (`kubectl`-only) path. And keep command *performance/operational* trivia (why a command is slow, which
  context) in the **Reference**; it's design-rationale weeds, not part of the Orientation's teaching flow.
- **Command output must be live; conceptual illustrations may show the *canonical* case.** The run-it rule
  governs command **output** — that must be real and captured. A concept diagram or table may instead
  depict the *typical / intended* shape even when the live system is currently sparser (a young reference
  platform often is) — teach the common case, not an accident of today's state. Just frame it as typical,
  and never dress an illustration up as live `$ command` output.
- **Illustrations must be domain-*coherent*, not just structurally valid.** An invented example still has
  to make real-world sense — respect dependencies, ordering, and causality. A grid showing a storefront in
  prod while its checkout dependency sits in dev is structurally fine but *logically* nonsense, and it
  teaches a wrong model. Sanity-check every illustration against how the domain actually behaves.
- **Verify *relational* claims, not just command output.** "X depends on Y", "X is newer than Y", "X
  causes Y" are all claims — check them against the system or the source (registry, ADR, live state), the
  same as a command. If you *can't* verify a relationship (e.g. the platform doesn't model inter-product
  dependencies), do not state it as fact — frame it **visibly** as illustration ("*say* `shop` calls
  `checkout`…"). Invented narrative that reads as verified fact is the subtlest failure mode: a reader
  can't tell it apart from the real claims, and "X is newer" is exactly the kind of thing that's quietly
  false against live data.

## Jargon sweep before shipping

The just-in-time-vocabulary rule (Orientation §5) is easy to *say* and easy to violate — borrowed terms
slip in as you write. So verify it as a **pass**, not by hoping you caught them inline: re-read the whole
module as a newcomer at its stated baseline, and flag every term you use as if known but never grounded
(namespace, cluster, admission, custom resource, tier, image, SSO, …). Ground each with a one-line gloss
at first use, or link the module that teaches it. Infra terms leak in constantly even when the *topic*
is conceptual — the audit catches what inline discipline misses.

**The shared glossary is a LOOKUP, not a substitute for grounding.** Cross-module substrate/domain terms
live once in the portal-wide `docs/learn/glossary.md` (linked from each module's Reference); module-specific
terms stay in that module's own Reference glossary. Either way it's look-up-later — it **complements, never
replaces** the just-in-time inline grounding (a glossary read cold is the front-loaded-vocab anti-pattern).

## Housekeeping

- Must pass `markdownlint-cli2` (repo `.markdownlint.yml`).
- Cross-link ADRs / runbooks / architecture with relative paths; reference house skills by name. There
  is no link-checker in CI — resolving links is on the author.
- Wire a new module into [the portal hub](README.md) and, per the `maintaining-docs` skill, into
  `docs/README.md`.
