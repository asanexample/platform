# ADR-099: Feature Flags as a First-Class Platform Service

**Date:** 2026-07-10

**Status:** Proposed

## Context

The platform has no native feature-flag capability, yet several shipped and planned features want one:

- **Progressive delivery** ([ADR-056](056-progressive-delivery-and-safe-rollback.md)) gates a *rollout*
  by metric, but there is no way to decouple a *feature's exposure* from its deploy — a flag-gated
  release, a percentage/ring rollout of behaviour, or an instant **kill switch** without a redeploy.
- **Operational toggles** (shed an expensive code path under load), **tenant entitlements** (which
  Product/Environment sees which capability), and eventually **experimentation** all need runtime
  configuration that is *not* a deploy.

Teams would otherwise hardcode this or reach for an external SaaS. The options are unappealing:

- **Commercial (LaunchDarkly)** — capable, but a recurring per-seat/MAU cost the reference platform
  shouldn't take on, and an external control plane outside our tenancy and identity model.
- **OSS wholesale** (Unleash, Flagsmith, GrowthBook) — each is a *product* with its own tenancy, auth,
  and UX that don't map onto `Team → Product → Environment`, and adopting one is another bespoke
  operational island with uneven eval/tenancy quality.
- **flagd alone** ([OpenFeature](https://openfeature.dev)'s CNCF evaluator) — an excellent *evaluator*
  and protocol, but deliberately *not* a product: no management API, no dashboard, no storage, no
  multi-tenancy, no audit.

The missing piece is specifically the **control plane and the product** — *not* the evaluation engine or
the client SDKs, which a CNCF standard already solves well. Forces:

- **Multi-tenant** — flags are per `Team → Product → Environment`, strictly isolated and RBAC-gated.
- **Polyglot** — Go (alpha e-commerce), TypeScript (bravo, future), Python — one client story for all.
- **Hot-path latency** — evaluation must be effectively free (no per-flag network round trip) and must
  survive the flag service being briefly unavailable.
- **Runtime-mutable, faster than a deploy *or* a PR** — a kill switch or a rollout change must take
  effect in **seconds**, not a `git commit → CI → Argo sync` cycle (minutes). This single force is what
  rules out a purely git-native flag store (see Alternatives) — it is the load-bearing reason this is a
  *service* and not another registry.
- **Editable by non-engineers** — a PM, an on-call responder, or a support lead must flip a flag from a
  **UI without opening a pull request**.
- **Dogfood the stack** — delivered on the platform's own delivery road, richly instrumented, and a
  flagship demonstration of the observability + progressive-delivery story.

## Decision

Build a **platform-owned feature-flag service** that owns the *control plane* and rides the standard
*data plane* — reinventing neither end.

### D1 — Stand on the OpenFeature standard; build no SDKs and no eval spec

Consuming apps use the **[OpenFeature](https://openfeature.dev) SDK** (the CNCF-standard, vendor-neutral
client API, mature in every language we run) with the **flagd provider**, and we adopt **flagd's flag
schema and evaluation semantics** as our data-plane contract. We write **zero** client SDKs and invent
**zero** wire format — apps are decoupled from our implementation and could swap to any OpenFeature
backend later. This is the "well-architected, not-too-fancy" line: reuse the proven client protocol the
way we reuse HTTP, and spend the effort on the product OSS lacks.

### D2 — Split the control plane from the data plane

- **Control plane (we build this):** a management API + dashboard to define flags, variations, targeting
  rules and environments; **CNPG Postgres** as the source of truth; an **audit log** of every change;
  **Keycloak**-backed RBAC scoped to `Team/Product/Environment`. This is the half every OSS option does
  poorly, and — honestly — the bulk of the work (see Consequences).
- **Data plane (mostly off-the-shelf):** flag **evaluation** is performed by **flagd** — as an injected
  sidecar or an in-process OpenFeature provider — against a per-Environment flag set our service
  publishes.

### D3 — Push-based delivery, local evaluation, fail-static

The control plane exposes a **sync source** per Environment (flagd's streaming sync API). The evaluator
holds the full Environment flag set in memory and **evaluates locally** — sub-millisecond, no per-eval
round trip — and receives changes over the stream, so a toggle propagates in ~seconds. If the flag
service is unreachable, evaluation continues against the last-known set (**fail-static**, never blocking
or fail-closing the caller's hot path). No app's request latency depends on us. A pod that starts *while
the control plane is unreachable* loads no set and evaluates to the **in-code defaults** the OpenFeature
call supplies — degraded (no targeting) but safe and non-blocking; it heals when the stream reconnects.

### D4 — Tenancy is the platform's existing model

A flag "environment" **is** a platform `Environment` (`Product × Stage`, [ADR-067](067-idp-domain-model.md)).
A flag is defined at `Team/Product` scope and **configured per Environment** (a flag can be `on` in `dev`
and a 5% rollout in `prod`), and access is RBAC-gated by the same identities. No new tenancy concept is
introduced. A flag's data lifecycle is coupled to its Environment's: decommissioning an Environment
([ADR-062](062-self-service-tenant-provisioning.md)) must GC its flag config via an explicit teardown
hook.

### D5 — A platform service on the one delivery road — with a scoped, cached sync topology

The service is a **platform-owned Product** delivered through the existing machinery
([ADR-081](081-platform-service-delivery.md)) — `gitops/products/platform/…`, the Environment
Composition, the per-Product ApplicationSet, promote + gate — placed on the **hub** (control plane +
Postgres + dashboard). No parallel road, no bespoke island.

Delivery to workload clusters is a **real design point, not a hand-wave**, and its constraints are
load-bearing:

- **Don't stream the hub to every pod.** Each workload cluster runs a small **sync relay/cache** that
  holds *one* upstream stream to the hub and re-serves the per-Environment flag sets locally; evaluators
  (sidecar or in-process) sync from the *local* relay. This keeps the hub off the tenant hot path,
  bounds per-cluster fan-out (instead of N-pods × M-services long-lived streams to the hub), and means a
  hub outage degrades only *flag changes* — the relay keeps serving last-known sets.
- **Scope and authenticate the stream.** A consumer receives **only its own `Product/Environment`** flag
  set, enforced by mutual-auth identity ([ADR-057](057-service-identity-and-east-west-zero-trust.md)) —
  there is no path by which one tenant streams another's flags.
- **Sidecar vs in-process** (a per-pod flagd sidecar for isolation, vs a shared per-node/namespace
  evaluator for footprint) is a build-time knob — deferred, but bounded by this topology.

### D6 — Observability-native by construction

- Every evaluation is emitted as **OTel span attributes** through OpenFeature's evaluation hooks
  (`feature_flag.key`, `feature_flag.variant`) — so a distributed trace shows *which variant a request
  ran*, tying flags directly to traces and to progressive delivery
  ([ADR-056](056-progressive-delivery-and-safe-rollback.md)).
- The service ships with **SLOs** (evaluation availability, change-propagation lag), dashboards, and
  alerts, and is a first-class consumer of the LGTM+P stack
  ([ADR-077](077-application-instrumentation-strategy.md)) — it *is* a flagship observability demo, not
  merely a user of one. Alpha's e-commerce Product is the first consumer (a flag-gated checkout variant).

### D7 — Lean v1 eval model, door left open

**v1:** boolean + multivariate (string/number/JSON) variations; an ordered rule list over the evaluation
context (attribute match) with a **default**; **percentage rollout** via **deterministic bucketing**
(consistent hash of a caller-supplied `targetingKey` → a stable variant, sticky across evaluations); and
a top-level **kill switch**. **Deferred but not precluded:** experimentation/statistics, approval
workflows, prerequisite flags, scheduled changes, and reusable segments. flagd's schema already models
most of these, so the door stays open without a redesign.

## Consequences

### Positive
- A real, owned platform primitive — no per-MAU tax, inside our identity/tenancy/observability boundary.
- Standards-based: mature multi-language SDKs for free; apps are never locked to our implementation.
- **Bounded build** — the *eval engine and SDKs are upstream*; we build only the control plane + sync
  source. Real work (see Negative), but a fraction of a from-scratch flag platform.
- Dogfoods and demonstrates progressive delivery + full-stack observability (flag→trace correlation).
- Decouples *release* (deploy) from *exposure* (flag): kill switches, ring rollouts, entitlements.

### Negative
- **The control plane is the bulk of the work, and it is real product engineering** — a management API,
  a targeting-**rule-builder UI** (flagd rules are JsonLogic, so the UI must compile *to* JsonLogic, not
  render a form), RBAC, an audit view, the multi-tenant sync source + per-cluster relays, and a
  dashboard. This is **weeks, not days**; underestimating it is the primary delivery risk. "Bounded"
  above is relative to building everything — it is not "small."
- We own stateful infrastructure (Postgres, audit) that must be backed up and kept available.
- A per-consumer flagd sidecar (if chosen over an in-process provider) adds a small resource + injection
  cost per workload.

### Risks
- **Cross-cluster delivery (D5) is the load-bearing subsystem** — the relay topology, the
  Environment-scoped stream authz, reconnection, and the cold-start-to-code-defaults path all have to be
  right, or we either leak flags across tenants or vary/block caller latency. Treat D5 as the risky
  *core*, not plumbing.
- **flagd schema coupling** — we adopt its semantics as our contract; a divergent upstream change could
  force a migration. Mitigated: the schema is CNCF-governed and stable, and we own the config source.
- **Deterministic bucketing needs a stable `targetingKey`** — rollouts are only sticky if the caller
  supplies a consistent key (user/session/tenant); anonymous flows (e.g. e-commerce browse) must mint
  and carry one, or a user's variant flaps per request.
- **Scope creep toward "fancy"** — segments/experimentation are a slippery slope; v1 is deliberately
  bounded (D7).

## Alternatives considered
- **flagd Kubernetes operator + `FeatureFlag` CRDs in git** — *the most on-brand option, and the one a
  sharp reviewer raises first.* Flags become git-native CRs like every other registry here
  (`Team/Product/Environment`), audited by `git log`, delivered by Argo, evaluated by flagd. It is
  **simpler** — no Postgres, API, or dashboard — and we would reach for it in a heartbeat **if the only
  requirement were release-gating**. It is rejected as the *primary* model by two Context forces: a flag
  change through `commit → CI → Argo sync` takes **minutes** (a kill switch must take seconds), and
  non-engineers must edit flags **without a PR**. We keep it in view two ways: as a possible
  *source-of-truth backend* the control plane could persist to (git-managed CRDs *plus* instant runtime
  overrides), and as the **honest fallback** if instant-toggle + non-engineer-UX turn out not to matter
  for v1 — in which case this ADR should be scaled back to it.
- **Adopt an OSS product wholesale (Unleash + Unleash Edge)** — the credible one, *not* a strawman:
  Unleash is OpenFeature-compatible and Edge gives local eval. Rejected because its
  project/environment/RBAC model is its own, mapped onto `Team/Product/Environment` only by convention +
  glue; we would still run and secure the operational island, fight its tenancy model, and inherit its
  UX. Building the control plane against *our* identity/tenancy is comparable effort with a coherent
  result — but this is the alternative most likely to be right **if the build proves heavier than
  estimated**, and the one to re-price against before committing.
- **Commercial (LaunchDarkly)** — rejected on recurring cost and an external control plane outside our
  tenancy/identity boundary.
- **flagd on its own** — rejected *as a product*: it is the evaluator, not the control
  plane/dashboard/multi-tenancy we actually need — which is precisely the half we build in D2.
- **Fully proprietary API + hand-rolled SDKs** — rejected: reinvents OpenFeature, locks apps to us, and
  makes SDK maintenance across three languages a permanent tax.

## Related
- [ADR-081](081-platform-service-delivery.md) — the platform-service delivery road this rides.
- [ADR-056](056-progressive-delivery-and-safe-rollback.md) — flags complement metric-gated rollouts.
- [ADR-067](067-idp-domain-model.md) — the `Team/Product/Environment` tenancy the flag model reuses.
- [ADR-057](057-service-identity-and-east-west-zero-trust.md) — the east-west path + identity the scoped sync stream uses.
- [ADR-077](077-application-instrumentation-strategy.md) — the observability stack the service dogfoods.
