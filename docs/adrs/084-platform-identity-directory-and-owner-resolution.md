# ADR-084: Platform Identity Directory and Owner Resolution

**Date:** 2026-06-26

**Status:** Proposed

## Context

The triage agent (ADR-080 / ADR-082) needs to route an incident to the human who should act — the
**author of the culprit commit**, falling back to the **owning team's on-call**. Building that surfaced
a latent platform gap: we have **auth identity** (Keycloak — ADR-053 / ADR-059), **team ownership**
(the git-native `Team` registry — ADR-067 / ADR-072), and external accounts (the GitHub org, the Slack
workspace, PagerDuty), but **no canonical directory of _people_ and their cross-system identities** that
integrations can query. There is no reliable bridge from "GitHub commit author" → "Slack `@mention`" →
"PagerDuty on-call."

Two realities shape the design:

1. **Email is not a reliable join key.** Most shops get away with matching identities by email; we
   cannot — in this org a person's GitHub, Slack, and PagerDuty emails differ. More generally it is a
   brittle assumption we refuse to bake in: a GitHub commit email is often a `noreply`, secondary
   emails are private (only `GET /user/emails` _as that user_), and nothing guarantees the same address
   across systems.
2. **We are on free GitHub/Slack tiers today**, with paid GitHub Enterprise + Slack (and their
   SAML/SCIM) a _future_ possibility. The design must work now and _upgrade_ cleanly later, not be
   rebuilt.

The naive fixes are all corners: a static config map the agent owns (stale, agent-private);
email-matching (brittle, and broken for us); or letting the agent own an identity table (every future
integration then duplicates / reconciles against it). The agent also needs durable state for adjacent
features — open-incident tracking, institutional memory, calibration — so the storage substrate is a
coupled decision.

## Decision

Treat identity as a **platform primitive**, not an agent feature.

**D1 — Identity is a platform concern; integrations are consumers behind an interface.** No integration
owns the identity record. Each resolves through a narrow
`resolveOwner({namespace, culpritGithubLogin?}) → {person?, team, on_call, tiers}` that returns identity
_facts only_. The triage agent is **consumer #1**. **Resolution (mechanism) is separate from mention
policy:** the resolver knows nothing of paging, severity, or disposition; a small reusable
`applyMentionPolicy(resolved, {severity, disposition})` helper applies the ladder + gate consumer-side
(D8). This keeps the shared resolver consumer-agnostic, and means a directory bug can never itself cause
an errant page — the page decision always lives with the consumer that has the incident context.

**D2 — Keycloak is the identity _anchor_ and the _linking engine_.** It remains the source of truth for
the person (`sub` / name) and brokers **GitHub, Slack, and PagerDuty as OAuth/OIDC identity providers**
(all three support social login on free tiers). Each brokered link is a first-class Keycloak
`FEDERATED_IDENTITY` carrying the provider's native id — GitHub **login**, Slack **user id**, PagerDuty
**user id** — explicit, email-free, **authoritative**. Reaffirms ADR-053 / ADR-059.

**D3 — Email is never a join key.** An external identity attaches to a `person` only by an _explicit_
assertion, never by inferring a shared attribute. Assertions carry a precedence **tier**:

| Tier | Source |
|------|--------|
| **authoritative** | Keycloak brokering / federated identity; future SAML-SCIM |
| **proven** | self-service OAuth link in an authenticated session |
| **declared** | reviewed admin / registry link |

(The earlier `heuristic` / email-match tier is **removed**.) Email is stored as a contact attribute
only — used for _nothing_ in resolution. `resolveOwner` returns the **highest-tier** link, and the tier
**gates action**: an `@mention` fires only at `declared`+; anything weaker degrades to a team mention or
plain text, so a guess can never page the wrong person.

**D4 — A thin Platform Directory is the SoT for operational handles + a least-privilege projection of
Keycloak identity.** Backed by Postgres (CloudNativePG). The model:

```text
person  (id, keycloak_sub, display_name)
  └─< external_identity (provider, external_id, external_username, tier, asserted_at)
  └─< team_membership   (team, role, tier)
workload_owner (namespace, product, team)    -- projected from Product + XEnvironment registries
```

It **syncs** Keycloak's federated identities → `external_identity` (so consumers never hold Keycloak
admin) and **owns** the handles Keycloak should not host. `resolveOwner` reads it. **PII lives here at
runtime — never in a git registry.** Because every identity anchors on the Keycloak person from first
login, there are **no stub records and no merging**.

**D5 — Onboarding linking is one-click OAuth, driven by Keycloak.** A new person logs into the platform
once; a **"Connect your accounts" step** (a Keycloak first-login required action, surfaced via
Backstage) links GitHub / Slack / PagerDuty with **one OAuth click each** — no codes, no typing, no
email. The directory syncs the resulting federated identities. This **supersedes a bespoke device-flow
bot**; the Slack bot demotes to an optional _nudge_ for stragglers that deep-links the same Account
Console. This is the most frictionless _reliable_ path; **true zero-touch** (no clicks) needs paid
SCIM/SAML — at which point provisioned links supersede the OAuth ones at the same `authoritative` tier,
with no redesign.

**D6 — Teams are the registry-anchored counterpart to Keycloak-anchored persons.** The `Team` registry
stays the SoT for the team (definition, ownership, and **non-PII handles** — `slack.channel`, optional
`slack.userGroup`); the directory projects it and holds `team_membership` (itself tiered:
registry-declared / SSO-group / GitHub org-team). The team is the **resolution floor** — every workload
maps to a team via `namespace → Product → Team` (ADR-067), so routing works on day one before anyone
has linked. The directory materializes this as a **`workload_owner(namespace, product, team)`
projection** synced from the `Product` + `XEnvironment` registries — **hub-central (git), so no
cross-cluster read** — with the ArgoCD Application's AppProject (`product-<team>-<product>`) as a live
fallback for namespaces not yet projected (platform/agent, ad-hoc). `resolveOwner(namespace)` is then a
single lookup, and `product`-then-`team` precedence is what lets a product override its team's on-call.

**D7 — On-call is resolved live from PagerDuty, not hardcoded.** PagerDuty is the system of record for
on-call. The `Team` / `Product` registry holds a **pointer** (`pagerduty.escalationPolicyId`), not
people; resolution queries PagerDuty `/oncalls` (cached, short TTL) → on-call user id → the directory's
`pagerduty` identity → person → `slack_id`. A registry-declared static contact is the **fallback** when
a team is not in PagerDuty or PagerDuty is unreachable.

**D8 — The owner-routing ladder is consumer-side policy.** `resolveOwner` returns the facts (D1); the
reusable `applyMentionPolicy` helper walks them highest-trust first:

```text
1. culprit author     <@…>            trusted person link (change-caused)
2. team on-call       <@…>            PagerDuty live → registry static
3. team user group    <!subteam^S…>   paid Slack (whole team)
4. team channel       post / @here    free
5. plain text         "owner: team"   floor
```

An `@mention` requires a trusted tier **and** `confident_lead` + critical severity; otherwise the owner
is named without a ping.

**D9 — Backstage is the human view, not the record.** It ingests person + handles from the directory
into its `User` / `Group` catalog and may surface the Keycloak Account Console for linking. It is **off
the incident path** — resolution never depends on the portal's availability.

**D10 — One Postgres substrate (CNPG + `pgvector`), shared but interface-isolated.** The same store
backs the directory and the agent's forthcoming **incident state**, **institutional memory** (vector
recall), and **calibration** — each behind its own interface, extractable later. Redis / NoSQL deferred
until a genuinely ephemeral or cross-replica-coordination need appears (the agent is single-replica
today).

**D11 — Freshness matches volatility; the directory is a rebuildable projection.** Every fact has a
system of record (Keycloak, the git registries, PagerDuty) — the directory only caches / denormalizes,
never authors — so there is **no dual-write to keep consistent**, and a corrupt or lost directory is
_rebuilt from source_, not a crisis. Two speeds: **slow / projected** data (identities, `team_membership`,
`workload_owner`, handles, the PagerDuty pointer) reconciles **periodically (~5 min**; the git-sourced
parts ride the existing registry-sync), with the team floor covering the gap if someone _just_ linked;
**on-call** is the one volatile fact — resolved **live from PagerDuty per query, short TTL (~1–5 min),
stale-if-error** (serve last-known / fall to the static contact, never fail the route). Keycloak identity
sync is periodic-reconcile for v1; event-driven push is a later enhancement.

**D12 — The culprit-author path fires only for a real, linkable, in-org human.** `get_change_detail`
yields the culprit commit's `author.login` (the SHA the model put in `culprit_change.ref`); before it is
trusted as a person it passes a filter: **bot / service accounts** (`[bot]` logins, `web-flow`, a known
CI-identity list) are excluded; **external / non-org** and **unlinked** authors have no trusted link. All
three degrade cleanly to the team floor. For an **unlinked org member**, the agent also DMs an
**incident-time nudge** ("you authored the change behind this incident — link your accounts"), turning
the miss into onboarding. Co-authored commits use the primary author; an author who is also the on-call
or a team member is deduped to a single mention; the `≥ declared` tier gate (D3) still applies.

**D13 — The directory is a scoped, audited, resolve-only API — never raw access.** It holds _identifiers,
not secrets_ (linking OAuth tokens are discarded, D5), so a leak is a privacy / targeting concern, not a
credential compromise — but PII still warrants discipline. Consumers reach it **only through
`resolveOwner`**, never the tables; the API **resolves but does not enumerate** (no "list all persons");
it **minimizes responses** to the operational handles a caller needs (`slack_id`, `team`, `on_call`) and
**never returns emails or the full identity set**. Three principal classes hold separate credentials —
_readers_ (resolve-only), _sync jobs_ (write, from the systems of record), _admins_ (manage). **Every
resolve is audited** (caller, input, returned tier) for provenance + abuse detection. While colocated in
the agent's Postgres the API is in-process; the `resolveOwner` interface is the boundary, so extraction
to a standalone service adds network authn (mTLS / scoped token) with no redesign.

**D14 — Data lifecycle: consent-by-linking, user-revocable, offboarding by pruning reconcile.** A
_proven_ link is the person's own OAuth act, which carries consent to store the handle for platform
routing; _authoritative_ / _declared_ links are org-provisioned. The person can **unlink** at any time
(same Account Console / bot surface) and the directory drops it. **Offboarding is automatic:** because
persons anchor on the Keycloak `sub` and the directory is a rebuildable projection (D11), a reconcile
that finds a person absent from the source **prunes the person + their links** — they stop resolving and
incidents fall to the team floor; no bespoke deletion machinery. The reconcile **prunes** (not
upsert-only), with a **mass-delete guardrail**: it refuses to prune when a sync returns suspiciously
empty / below a sanity threshold, treating that as a source failure rather than "everyone left."

## Consequences

### Positive

- Identity is a reusable **platform capability** — the next integration consumes `resolveOwner`; it
  does not rebuild a map.
- **Frictionless, reliable onboarding** — one-click OAuth per provider, no email, no codes; authoritative
  links land on the canonical person with no stubs or merges.
- **No brittle assumptions** — email is never load-bearing; nothing breaks when addresses differ across
  systems.
- **Least privilege** — consumers hit a scoped resolve API, never Keycloak admin; the auth control plane
  holds no operational metadata.
- **Posture intact** — Keycloak brokering + cached PagerDuty reads add no inbound surface to the agent.
- **Upgrades cleanly** — paid SAML/SCIM and Slack user-groups slot into existing tiers; live PagerDuty
  replaces static on-call — none of it a redesign.

### Negative

- New (small) platform pieces to own — the directory schema, the Keycloak brokering config for three
  providers, the PagerDuty / Keycloak sync, the Backstage projection.
- Linking is one-click but **not zero-touch** until paid SCIM/SAML; people must connect their accounts
  once (driven at onboarding).
- A directory the agent writes to is new mutable state vs. the prior statelessness.

### Risks

- **Memory poisoning** — injected incident content could write a misleading "past triage"; institutional
  memory must be consumed as _evidence, never instructions_. (Identity writes are constrained to
  authoritative / proven / declared sources, never model-driven.)
- **PII custody** — the directory holds handles; access-controlled, internal-only, not in git.
- **PagerDuty dependency** — live on-call lookups must be cached + fall back to a static contact so
  PagerDuty downtime degrades gracefully; presumes PagerDuty actually has schedules / escalation
  policies configured (not merely used as an alert sink).
- **Scope creep** — mitigated by seed-not-cathedral sequencing: directory + `resolveOwner` +
  registry-floor first; brokering, projection, PagerDuty, and memory as consumers pull.

## Alternatives considered

- **Static, agent-owned config map.** Rejected: stale, agent-private, not org data.
- **Email as the join key.** Rejected: brittle in general and _broken for us_ (our GitHub / Slack /
  PagerDuty emails differ); commit emails are often `noreply` and secondaries are private. Email is
  stored as contact info, never a matcher.
- **Bespoke Slack device-flow linking bot.** Superseded: Keycloak brokering is smoother (one OAuth click
  vs. a device code), reuses native machinery, and lands _authoritative_ links on the canonical person.
- **Backstage as the directory of record.** Rejected: its catalog is a source-fed projection, not a
  transactional store, and it is a developer portal we will not place on the incident-routing path. It
  is the human _view_, fed from the directory.
- **Keycloak as the universal directory.** Rejected for the _operational_ layer: serving every
  integration from Keycloak forces Admin API access on consumers and mixes operational metadata into the
  auth control plane. Keycloak stays the _anchor_ + linking engine; the directory is the least-privilege
  projection + handle store in front of it.
- **Hardcoded on-call lists.** Rejected: PagerDuty is the system of record for on-call; a static list has
  no rotation / escalation. A registry pointer + live PagerDuty (with static fallback) replaces it.
- **Redis / NoSQL as the primary store.** Rejected now: the data that needs a database (directory +
  memory + calibration) is relational + vector (Postgres + `pgvector`); JSONB covers document
  flexibility; the one Redis-shaped workload (ephemeral incident state) is tiny and single-replica.

## Sequencing

Value is tiered by effort; each phase adds a resolution _source_ behind the stable `resolveOwner` /
`applyMentionPolicy` interface — never a rebuild (seed-not-cathedral).

**Phase 0 — the team floor (no new datastore).** Config / registry-derived only — no Postgres, no PII.

- **Extend the `Team` schema with the ownership block** (`slack.channel` / `slack.userGroup`,
  `pagerduty.escalationPolicyId`, accountable roles) and **equip the `platform` team first** — it is the
  resolution floor for every platform-owned incident, _including the agent's own_ (`team=platform`), which
  today routes nowhere.
- `resolveOwner(namespace)` derives `namespace → product → team` and routes to the team's `slack.channel`.
  The `workload_owner` projection sources tenant namespaces from the Product / XEnvironment registries
  (+ ArgoCD fallback) **and platform namespaces from the platform Products / XAgent registry** (platform
  teams deploy XAgents, not XEnvironments).
- → Every incident routes to its owning team; proves the interface.

**Phase 1 — directory + author precision.** Stand up CNPG Postgres + the `person` / `external_identity`
schema; Keycloak brokers GitHub (+ Slack); the onboarding "connect accounts" step; the directory syncs
federated identities. `resolveOwner(culpritGithubLogin)` mentions the culprit author at a trusted tier
(D12 filters + nudge). Postgres arrives exactly when person-identity PII needs a home.

**Phase 2 — live on-call.** PagerDuty brokered as a `pagerduty` identity + the registry escalation-policy
pointer; live on-call resolution (cached, stale-if-error).

**Phase 3 — polish & extract.** Backstage projection (the human view), event-driven Keycloak sync, and
extraction of the directory to a standalone service when a second consumer appears.

Start at Phase 0 — highest value-per-effort, and equipping the platform team first means the agent's own
incidents (and all platform-owned ones) route somewhere real before we touch PII / Postgres / brokering.

## Related

- [ADR-053](053-identity-and-cross-system-authorization-strategy.md) /
  [ADR-059](059-identity-topology-pluggable-idp-seam.md) — Keycloak identity strategy / pluggable seam
  (the anchor + brokering engine this builds on).
- [ADR-080](080-triage-copilot.md) / [ADR-082](082-platform-agent-runtime-xagent.md) — the triage agent
  / `XAgent` runtime (consumer #1; owner-routing is the first feature).
- [ADR-072](072-app-repo-naming-and-team-ownership.md) — app-repo naming & GitHub org-Team ownership (the
  team side of resolution; the org-team membership source).
- [ADR-067](067-idp-domain-model.md) / [ADR-061](061-tenant-ingress-and-custom-domain-strategy.md) —
  registries-as-source-of-truth (the pattern this extends — and deliberately diverges from for runtime
  PII).
