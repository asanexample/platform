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
  poorly, and the half worth owning.
- **Data plane (mostly off-the-shelf):** flag **evaluation** is performed by **flagd** — as an injected
  sidecar or an in-process OpenFeature provider — against a per-Environment flag set our service
  publishes.

### D3 — Push-based delivery, local evaluation, fail-static

The control plane exposes a **sync source** per Environment (flagd's streaming sync API). The evaluator
holds the full Environment flag set in memory and **evaluates locally** — sub-millisecond, no per-eval
round trip — and receives changes over the stream, so a toggle propagates in ~ms. If the flag service is
unreachable, evaluation continues against the last-known set (**fail-static**, never blocking or
fail-closing the caller's hot path). No app's request latency depends on us.

### D4 — Tenancy is the platform's existing model

A flag "environment" **is** a platform `Environment` (`Product × Stage`, [ADR-067](067-idp-domain-model.md)).
Flags are namespaced by `Team/Product`, configured per Environment (a flag can be `on` in `dev` and a 5%
rollout in `prod`), and access is RBAC-gated by the same identities. No new tenancy concept is introduced.

### D5 — It is a platform service on the one delivery road

The service is a **platform-owned Product** delivered through the existing machinery
([ADR-081](081-platform-service-delivery.md)) — `gitops/products/platform/…`, the Environment
Composition, the per-Product ApplicationSet, promote + gate — placed on the **hub** (control plane +
Postgres + dashboard). Its per-Environment **sync source** is reachable from workload clusters over the
existing east-west path ([ADR-057](057-service-identity-and-east-west-zero-trust.md)); sidecar/provider
wiring is injected onto consuming workloads via the paved road. No parallel road, no bespoke island.

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
(consistent hash of a context key → a stable variant, sticky across evaluations); and a top-level
**kill switch**. **Deferred but not precluded:** experimentation/statistics, approval workflows,
prerequisite flags, scheduled changes, and reusable segments. flagd's schema already models most of
these, so the door stays open without a redesign.

## Consequences

### Positive
- A real, owned platform primitive — no per-MAU tax, inside our identity/tenancy/observability boundary.
- Standards-based: mature multi-language SDKs for free; apps are never locked to our implementation.
- Small build surface — we own a control plane + a sync source; the eval engine and SDKs are upstream.
- Dogfoods and demonstrates progressive delivery + full-stack observability (flag→trace correlation).
- Decouples *release* (deploy) from *exposure* (flag): kill switches, ring rollouts, entitlements.

### Negative
- We own a stateful control plane (Postgres, audit, RBAC, a dashboard) — real, ongoing software.
- A per-consumer flagd sidecar (if chosen over an in-process provider) adds a small resource + injection
  cost.
- One more service to run, secure, and keep available (though hot-path evaluation is fail-static).

### Risks
- **flagd schema coupling** — we adopt its semantics as our contract; a divergent upstream change could
  force a migration. Mitigated: the schema is CNCF-governed and stable, and we own the config source.
- **Cross-cluster sync path** — the hub control plane must reach workload-cluster evaluators reliably;
  the stream must reconnect cleanly and evaluation must fail-static meanwhile. This is a hard design
  requirement, not an optional nicety.
- **Scope creep toward "fancy"** — segments/experimentation are a slippery slope; v1 is deliberately
  bounded (D7).

## Alternatives considered
- **Commercial (LaunchDarkly)** — rejected on recurring cost and an external control plane outside our
  tenancy/identity boundary.
- **Adopt an OSS product wholesale** — rejected: none fit `Team/Product/Environment`, each is another
  operational island with its own auth/UX, and eval/tenancy quality is uneven.
- **flagd on its own** — rejected *as a product*: it is the evaluator, not the control
  plane/dashboard/multi-tenancy we actually need — which is precisely the half we build in D2.
- **Fully proprietary API + hand-rolled SDKs** — rejected: reinvents OpenFeature, locks apps to us, and
  makes SDK maintenance across three languages a permanent tax.

## Related
- [ADR-081](081-platform-service-delivery.md) — the platform-service delivery road this rides.
- [ADR-056](056-progressive-delivery-and-safe-rollback.md) — flags complement metric-gated rollouts.
- [ADR-067](067-idp-domain-model.md) — the `Team/Product/Environment` tenancy the flag model reuses.
- [ADR-057](057-service-identity-and-east-west-zero-trust.md) — the east-west path the sync stream uses.
- [ADR-077](077-application-instrumentation-strategy.md) — the observability stack the service dogfoods.
