# ADR-073: Self-Service Cloud Resources (the resource paved road)

**Date:** 2026-06-17

**Status:** Accepted (2026-06-17)

## Context

Self-service **products** and **environments** work end-to-end today (New Product / New Environment → gated PR →
Crossplane Composition → running, signed workload). The next gap is **self-service cloud resources**: letting a
dev team provision the AWS building blocks their workload needs — an S3 bucket, an SQS queue, an SNS topic, a
DynamoDB table — while:

- **abstracting Crossplane, AWS, and IaC away from the developer** as much as possible;
- keeping the **platform team out of the per-request path** (no ticket-and-wait); and
- staying **safe, secure, governed, and compliant**.

The hard part is not plumbing — Crossplane already provisions. The hard part is the tension between **aggressive
abstraction** (developers should not have to understand Crossplane/IAM/AWS) and **hard governance** (nothing
unsafe, cross-team, or runaway-costly may be created). This ADR resolves that tension and names an **agentic**
front door as the longer-term direction.

### The seam already exists

The `XEnvironment` XRD carries a **reserved** block
(`infra/modules/crossplane/charts/environment-api/templates/xenvironment-xrd.yaml` ~L202, ADR-067 §7):

```yaml
services.<svc>.resources:        # "Reserved (ADR-067 §7): cloud-neutral Service→Resource deps; inert until the
  <name>:                        #  data paved-road ships."
    kind:  relational | cache | objectstore | stream   # cloud-NEUTRAL category
    engine: <string>             # e.g. s3, sqs, sns, dynamodb
    class:  <string>             # engine-specific size/shape
    isolation: shared | dedicated
```

This ADR **activates that block** as the governed contract.

## Decision

Insert a **governed intermediate representation (IR)** — the high-level, cloud-neutral, bounded resource claim
above — as the single contract between two halves:

- **Everything *above* the claim is intent capture** — how a developer expresses what they want. Interchangeable
  and as abstract as we like (a Backstage form, a hand-authored PR, eventually a natural-language agent).
- **Everything *below* the claim is safe realization** — how the platform turns it into real cloud resources.
  Deterministic, platform-owned, and entirely hidden from developers.
- **The claim is validated in the middle** by the gitops Gate + Kyverno + the Team envelope.

This dissolves the abstraction-vs-safety tension: **abstraction lives entirely above the claim; safety lives
entirely below it.** A front door can be arbitrarily magical without touching the safety floor, because every
front door must produce the same governed claim, and the claim is what gets validated and realized.

```text
  INTENT CAPTURE (above — abstract, swappable)
    Backstage form   ·   direct PR (as-code)   ·   NL agent (Phase B, maximal abstraction)
            +---------------- all PRODUCE v ----------------+
  +-------------------------------------------------------------------+
  |  THE GOVERNED CLAIM (IR) — cloud-neutral resource block           |  <- single safety boundary
  |  validated by: gitops Gate + Kyverno envelope + Team envelope     |
  +-------------------------------------------------------------------+
            +---------------- REALIZED BY v ----------------+
  SAFE REALIZATION (below — deterministic, platform-owned, AWS/Crossplane HIDDEN)
    Crossplane Compositions (safe-by-construction) -> AWS resources + platform-derived least-privilege IAM
```

The platform team authors a Composition **once per resource type** and sets envelopes; after that, dev teams
self-serve within the envelope with no per-request approval. That is how the platform stops being the bottleneck.

## Realization (below the claim — build now)

Deterministic on purpose: auditable, never "creative," fully hidden from developers.

- **Curated Crossplane Compositions per resource type**, rendered inside the existing Environment Composition
  (`files/composition.yaml`) — not a separate XRD — so a resource shares its Environment's lifecycle. Safe-by-
  construction and non-overridable: public access blocked, TLS-only, versioning / PITR, region pinned, and
  standard cost-attribution tags (`Team`/`Product`/`Stage`/`Service`).
- **Encryption is tiered** (the KMS decision): `standard`-tier resources use service-managed encryption (SSE-S3 /
  SSE-SQS / DynamoDB default) — zero key cost/ops; regulated tiers (elevated/pci/hipaa) use a **per-team CMK**
  whose key policy is scoped to that team's roles (cryptographic tenancy isolation + audit + revocation), built
  when the first regulated tenant lands. The Composition selects the key from the tier.
- **Names are platform-controlled** (`refplat-<team>-<product>-<stage>-<name>`, truncate+hash to fit each
  service's length limit). **S3** (globally-unique names) additionally gets a **deterministic hash suffix** of
  `account-id` + the identity tuple — globally unique, unpredictable (defeats bucket-sniping), and *stable across
  re-creates* so a re-declared resource cleanly adopts its orphaned bucket; per-account services keep the
  friendly name.
- **Outputs → workload:** the Composition writes a non-secret `<svc>-resources` ConfigMap (e.g. `DOCS_BUCKET=…`,
  `EVENTS_QUEUE_URL=…`) and the scaffolder skeleton auto-wires `envFrom` (`optional: true`) — k8s-native, no
  resolver (auth is Pod Identity; no creds). A Secret/ESO path is reserved for credentialed engines (RDS, later).
- **`deletionPolicy: Orphan`** by default (mirrors ECR) — no accidental data loss on decommission; destructive
  delete is an explicit, gated action (see Security & safety → lifecycle).
- **Access by *derivation*, never author input** (the security crux): the Composition computes the exact scoped
  IAM for the provisioned ARN and injects it into the service's Pod-Identity `RolePolicy` (the existing
  `composition.yaml` ~L389 seam). Developers never write resource IAM.
- **Governance pipeline:** gitops Gate (shift-left) + Kyverno `restrict-environment-envelope` (admission) + the
  **Team envelope** (allowed engines, count caps, isolation floor) + **tiered auto-merge** (low-risk in-envelope
  auto; prod / regulated / costly → human review) + lifecycle/data-safety.
- New providers on the **preprod (workload) `crossplane` unit**: `provider-aws-{s3,sqs,sns,dynamodb}` (functions
  `go-templating`/`environment-configs`/`auto-ready` already present).

### Extensibility is a first-class principle

The first four services are a **seed catalog, not the architecture's limit** — the spine is a general
resource-provisioning framework, not "an S3 feature":

- Growing the catalog is a playbook, not a re-architecture: add a Composition + an envelope entry + catalog
  metadata per new type (RDS, ElastiCache, OpenSearch, EventBridge, …). The platform team's recurring job is
  *curating the catalog*, not *handling requests*.
- The IR is extension-friendly: beyond `kind`/`engine`/`class`/`isolation`, carry an engine-specific **`params`
  map** validated *per-engine*, plus an **`access` intent** (`read` / `readwrite`), so adding a type or option
  does not churn the XRD schema and access stays least-privilege.
- Catalog edges do not trap the developer: when a need exceeds the catalog, Backstage (and the Phase-B agent)
  surface the closest fit and route a **structured request to the platform team** to add a Composition.

We start narrow to get the *safety + governance machinery* right on low-blast-radius resources, then scale
breadth — not because the design is limited to them.

## Intent capture (above the claim — the front-door spectrum)

All three produce the *same* governed claim and pass the *same* validation:

1. **Backstage form (build now).** Pick from a catalog ("object storage for user uploads") with a few bounded
   knobs → renders the `services.<svc>.resources` block → gated PR. Crossplane/AWS fully hidden. The common case.
2. **Direct claim authoring (build now).** A PR editing the resources block — for power users / multi-resource
   changes. The developer sees the cloud-neutral claim (a thin, friendly schema), never raw Crossplane.
3. **Agentic natural-language front door (Phase B).** A **bespoke, conversational** Backstage-integrated
   assistant (Claude API) that **acts like a platform engineer**: it elicits requirements through dialogue, helps
   a developer who does not yet know what they need, weighs tradeoffs (cost, isolation, class), and **co-authors
   the governed claim iteratively**. The developer reasons about their *problem* ("users upload files we process
   in the background"), not infrastructure; the agent drafts the claim, explains what it will create + the cost /
   blast-radius, the developer confirms, and it opens the **gated PR**. It is the platform team's expertise made
   always-available and self-service. A **sibling ADR will detail the agent when it is built**; this ADR names it,
   reserves the seam, and fixes its safety boundary (below).

The front-door set is **open-ended** — the governed claim is the only contract, so any channel that produces it
inherits the entire safety floor. A natural future addition (especially for the Phase-B agent) is a **Slack/chat
surface**, letting a developer describe a need in Slack and the agent co-author the claim → gated PR there. It is
a *future consideration* — no Slack workspace exists yet — and it changes nothing below the claim; it is simply
another producer of the same IR.

## Security & safety

The entire model rests on one invariant: **the governed claim is the only way to provision, and it is validated
and realized by platform-owned machinery.** Specifics:

- **Bound the Crossplane provisioner role.** Creating buckets/queues/tables needs broad create/delete power — a
  high-value target. Scope the provisioner role to *only the catalog's services*, with a **`refplat-*` name-prefix
  condition** and a **permissions boundary**, so a compromised Composition/provider cannot create arbitrary or
  non-platform resources. (Today's `crossplane-provisioner` role already manages ECR **and** the per-environment IAM roles — name-prefix-scoped, permissions-boundary-capped; widen it to the new resource services under that same discipline.)
- **Least-privilege by derivation + explicit `access` intent.** Runtime access is computed by the Composition
  from the provisioned ARN and the claim's `access` field — minimal verbs, scoped to that ARN only. Developers
  never author resource IAM; the deny-set-validated `permissions.aws.policyStatements` remains only as a bounded
  escape hatch.
- **Tenancy isolation (guaranteed + tested).** Platform-controlled names + derived ARNs (never author-supplied)
  structurally prevent one team referencing or accessing another's resource. A negative test asserts team A
  cannot read/attach team B's resource.
- **Defense in depth — gate *and* Kyverno.** The resource rules (allowed engines, isolation floor, count caps,
  access intent) are enforced both shift-left (gitops Gate) and at admission (Kyverno `restrict-environment-
  envelope`), so a gate bypass is still caught; the control-plane backstop already blocks non-platform principals
  from creating `XEnvironment`.
- **Compliance tiers drive *config*, not just review.** `standard` uses service-managed encryption;
  elevated/pci/hipaa force a **per-team CMK** + access logging + residency, applied by the Composition from the
  tier — not merely a review flag.
- **Secrets / output sensitivity.** The first four use Pod Identity (no static creds) → non-secret ConfigMap
  outputs (`<svc>-resources`, consumed via `envFrom`). Credentialed engines (RDS, later) need a Secret/ESO path;
  the binding layer distinguishes secret vs non-secret outputs from the start.
- **Lifecycle / data safety.** Removing a resource from the claim deletes the managed resource but, with
  `deletionPolicy: Orphan`, the AWS resource + data survive. True destruction is an explicit, gated, decommission-
  first action (reusing the Deprovision Product/Environment pattern, ADR-062).
- **Cost is an abuse/DoS surface, not only a finance one.** A buggy/hostile actor (or a hallucinating agent) can
  blow up spend. Per-Environment count caps + tiered review are the Phase-A guardrails; **hard dollar budgets and
  the aggregate-per-team cap are owned by the Cost Management effort** (the standard cost tags make resources
  attributable so those budgets work when they land). **Orphaned resources accrue cost**: a tag-based audit/GC of
  `refplat-*` resources with no owning claim flags them for cleanup.

### Agent-layer safety (Phase B — named here, detailed in the sibling ADR)

- **Autonomy (principle, decided):** the agent always **drafts → explains (cost / blast-radius) → the requesting
  human confirms** before any PR opens; it never auto-applies and has no privilege to merge. The confirmed PR
  then runs the existing tiered gate. Whether a confirmed *low-risk* PR auto-merges vs. always pulls a second
  reviewer is a Phase-B detail deferred to the sibling ADR.
- **The agent emits only the governed claim — never raw Crossplane/AWS IaC — and has zero infrastructure
  privilege** (read-only context tools + open-a-PR). So a hallucination or **prompt injection** can at worst
  produce a claim the gate/Kyverno *reject* — never an unsafe, public, or cross-team resource, and never an
  escalation. This mirrors the proven "constrain-then-verify" pattern, where our existing governance pipeline is
  the verifier.
- **Agent-drafted PRs must NOT ride the bot auto-merge path.** Otherwise the agent could auto-provision without
  the human confirm, defeating human-in-the-loop. Agent PRs require the requesting human's approval; auto-merge
  stays only for the deterministic low-risk path the human already confirmed.
- **Agent context is scoped to the requester's team** (mirroring `verify-team-membership`) so it cannot leak
  another team's resources or topology.

## Phasing

1. **Phase A — the deterministic backbone (must come first).** Realization + the claim IR + the Backstage form +
   direct-PR authoring + governance, on **S3 first**, then SQS / SNS / DynamoDB. The agent is worthless without a
   safe claim pipeline to target.
2. **Phase B — the agentic front door (additive, low-regret).** Once the claim contract is proven, add the
   conversational agent (sibling ADR). If it underperforms, fall back to the form/PR with zero loss — it is just
   another claim producer.
3. **Later — stateful/networked (RDS/Aurora/ElastiCache).** Separate ADR: backups, restore, subnet groups, secret
   rotation, heavier cost/safety review.

## Consequences

### Positive

- Realizes the ADR-067 §7 Service→Resource model on the seam reserved for it — minimal new surface.
- The platform team is no longer per-request: author a Composition once per type + set envelopes; teams self-serve.
- Security by construction: bounded provisioner role + platform-derived least-privilege IAM + safe Composition
  defaults + Orphan-by-default. Blast radius is one resource, one role.
- One governed contract serves every front door (form, PR, agent) — the agent is the maximal abstraction without
  weakening the safety floor; no re-plumbing to add it.
- A general, extensible framework — the seed catalog is a floor, not a ceiling.

### Negative / costs

- New providers on the workload cluster — more CRDs, memory, upgrade surface, and AWS API reconcile load at scale.
- The Composition go-template grows non-trivially (per-engine rendering + IAM derivation + outputs) — needs strong
  tests.
- Cost control is bounded (count caps + tiered review), not measured — real visibility/budgets are a follow-on.
- A second governance vector (resources) to keep in lock-step across gate + Kyverno + envelope.
- The Phase-B agent is a build-and-maintain commitment (deferred, but real).

## Alternatives considered

- **A separate `XResource` XRD/claim per resource** — rejected for now: resources belong to an Environment's
  lifecycle; a sibling claim duplicates ownership/envelope wiring and risks orphans.
- **Developers write raw `policyStatements` for resource access** — rejected: author-supplied IAM is the
  escalation risk the deny-set fights; platform-derived least-privilege is strictly safer.
- **An agent that writes raw Crossplane/AWS IaC** — rejected: discards every Composition guardrail; the agent
  could emit anything. The agent must target the governed claim.
- **An agent with cloud credentials / direct apply** — rejected hard: never give an LLM provisioning privilege;
  it stays above the claim boundary, with no infra access.
- **Buy an existing NL→IaC/agent platform** (StackGen / Firefly / Gengineer) instead of building — set aside:
  they tend to emit raw IaC and bring their own governance, which fights this model. Build bespoke against our
  claim instead (Phase B).

## Decisions (key questions resolved 2026-06-17)

- **KMS:** service-managed encryption for `standard`; **per-team CMK for regulated tiers** (key policy scoped to
  the team's roles), built when the first regulated tenant lands. (Per-team, not per-environment, granularity —
  revisit only if per-env isolation is ever required.)
- **Cost:** per-Environment count caps + tiered review + cost-attribution tags in Phase A; **hard dollar budgets
  and the aggregate-per-team cap are owned by the Cost Management effort**, not reinvented here.
- **Output binding:** ConfigMap `<svc>-resources` + `envFrom`, auto-wired by the scaffolder skeleton; no resolver
  (revisit only on a concrete ergonomics need).
- **S3 naming:** deterministic hash suffix (`account-id` + identity), truncate+hash to 63 chars; friendly names
  for the per-account services.
- **Agent autonomy (Phase B):** principle locked — always draft → explain → human-confirm → tiered gate; zero
  infra privilege; never auto-applies. The auto-merge-after-confirm vs. always-second-reviewer nuance is deferred
  to the sibling ADR.

## Verification (for the eventual build, per phase)

- Composition render tests (`infra/modules/crossplane/.environment-api-tests`) — safe defaults forced; derived
  IAM scoped to the resource ARN only.
- `.kyverno-tests` for the new envelope rules + gate unit tests (`test-validate-environments`).
- E2E on preprod: front door → gated PR → resource Ready → workload reads/writes via Pod Identity → cross-team
  access denied (negative) → decommission leaves data (Orphan) → gated purge destroys it.
- Phase B: the agent drafts a valid claim for a sample intent; an intentionally-bad intent yields a claim the gate
  *rejects* (proving the boundary holds); the agent cannot open a PR that bypasses the gate.

## Related

- Realizes [ADR-067](067-idp-domain-model.md) §7 (Service→Resource dependency model, the reserved block).
- Builds on the Crossplane Environment Composition (`docs/architecture/crossplane-environment-api.md`, ADR-046/048),
  Pod-Identity access (ADR-041/047), the envelope + deny-set governance (ADR-062), and the gitops Gate.
- Backstage is the UI (ADR-051). The Phase-B conversational agent gets its own ADR when built.
