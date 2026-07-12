# ADR-101: `ServiceGrant` — A Governed Cross-Team Network Capability

**Date:** 2026-07-12

**Status:** Proposed — direction agreed, not yet built. **Not rebuild-gated**: the rebuild-gating on
[ADR-068](068-product-scoped-and-cross-team-access-model.md) is specifically about the Keycloak/OIDC
human-identity cutover, which this capability doesn't touch at all — it is pure Crossplane + Kyverno and
independently buildable now. Flip to Accepted once built and the admission policies (Part 2) are enabled.

## Context

Cross-namespace service-to-service traffic on this platform is governed by paired CiliumNetworkPolicies — an
egress half in the caller's namespace, an ingress half in the callee's ([ADR-057](057-service-identity-and-east-west-zero-trust.md)).
For a **cross-team** call (different owning teams, not just different stages of the same Product), every one of
these pairs has so far been **hand-authored per app repo**: each team writes its own half, by hand, with no
shared mechanism keeping the two sides in sync. That's fragile — the two halves can drift, and there is no
single place that shows "who currently has network access into my service." It already caused a real incident
on a *simpler* case: a tenant calling a **platform**-owned service (not even a peer team) still needed a
hand-authored CNP pair, and the two halves fell out of sync in a way that silently broke the call.

Cross-team dependencies are not expected to be a one-off here — they're the **common** shape in this
platform's target enterprise use case (independent teams' Products calling each other's services). Continuing
to hand-author CNP pairs per integration doesn't scale past a handful of cases and leaves cross-team network
exposure effectively unauditable.

The platform's own governance model has already anticipated this without building it. [ADR-090](090-governance-identity-model.md)'s
layer glossary (D1/D5) classifies `AccessGrant` ([ADR-068](068-product-scoped-and-cross-team-access-model.md))
as belonging to the **"Machine / service access"** layer — "workload-to-workload, not human" — distinct from
the human-developer access model ADR-068 actually specifies. That reclassification was correct but aspirational:
no reconciler was ever built against it. `AccessGrant` remains a plain, unreconciled CRD whose one real intended
consumer (a generic cross-team access primitive) never materialized against a *network* capability, and its
schema — `subject: user:<id> | group:team-<b>`, `posture: view|operate` — is shaped for human RBAC (who can
read/operate a namespace via Backstage/ArgoCD/kubectl), not for "which pod may reach which port on which other
pod." Bending `AccessGrant` to also carry network capability would overload a schema that already has a clear,
different job.

This ADR gives ADR-090's "workload-to-workload" reclassification an actual mechanism, scoped specifically to
network capability, and makes cross-team service dependencies a governed, low-friction, auditable golden path
instead of a hand-authored one-off every time two teams need to talk.

## Decision

Introduce **`ServiceGrant`**, a new git-native primitive that lets a producer team grant a consumer team's
service network access to one of its own services, and a dedicated Crossplane reconciler that turns an approved
grant into the two CiliumNetworkPolicy halves automatically — so an app team never hand-writes a cross-team CNP
again.

### D1 — A sibling kind, not an `AccessGrant` extension

`ServiceGrant` is a **new, separate** Crossplane composite kind, not a schema extension of `AccessGrant`.
`AccessGrant`'s `subject`/`posture` shape is built for human RBAC and doesn't fit a machine-to-machine network
capability (ports, protocol, optional L7 method/path narrowing, no "posture" concept at all). Per
[ADR-090](090-governance-identity-model.md) D4's own precedent — keep `AccessGrant` as-is and resolve the
naming overlap with a glossary rather than force a rename or a schema merge — `ServiceGrant` sits alongside
`AccessGrant` on the same "machine / service access" layer as a distinct object with its own schema:

```yaml
kind: ServiceGrant
spec:
  target:   { team, product, stage, service }   # producer — whose namespace admits traffic
  subject:  { team, product, stage, service }   # consumer — whose namespace gets egress
  capability:
    network:
      ports: [int]
      protocol: TCP | UDP
      http:                                     # optional L7 narrowing; omit = any path/method
        - { method: string, path: string }
  expiresAt: <string, optional>
```

`AccessGrant` itself is **not edited or amended** by this ADR.

### D2 — Its own small, single-responsibility Composition

`ServiceGrant` gets a **new, standalone** Crossplane chart and Composition (sibling to `environment-api` /
`agent-api`), deliberately **not folded into the existing `environment-api` Composition**. `environment-api` is
already the platform's largest and most complex Composition; adding cross-team network reconciliation to it
would make both harder to build, test, and reason about, for no shared benefit — a `ServiceGrant` is a pure
function of its own spec (no cross-XR reads are needed, since Crossplane's `provider-kubernetes` already has
cluster-wide write RBAC to create the two CNPs directly). A small, isolated Composition is easier to land, test
in isolation, and reason about independently of the environment lifecycle.

### D3 — The end-to-end mechanism: two separate declarations, one reconciler

1. The **producer** team authors the `ServiceGrant` in their own git domain (`gitops/grants/<target.team>/`) —
   "team bravo grants alpha's `orders` service access to my `intake` service." Authorization is directory-based,
   the same pattern the gitops-gate already uses elsewhere: the PR's directory must match `spec.target.team`,
   since the producer is the one consenting to admit traffic, not the consumer.
2. The **consumer** team separately declares the dependency on their own `XEnvironment` claim
   (`spec.dependencies: [{team, product, stage, service}]`) — reusing the Product/Environment granularity
   [ADR-067](067-idp-domain-model.md) already establishes. This is self-documenting (a reviewer can see a
   Product's cross-team dependencies in its own claim) and encodes mutual consent: declaring a dependency alone
   grants nothing, and a grant alone doesn't force the consumer to depend on it. It's not required for the
   underlying network access to function, but it *is* required to pass the admission gate below.
3. A dedicated reconciler watches `ServiceGrant` objects and materializes **both** CNP halves — egress in the
   consumer's namespace, ingress in the producer's — using the deterministic `team-product-stage` namespace
   naming already established by `environment-api`. Both CNPs are owned by the `ServiceGrant` XR, so deleting
   the grant tears down both halves via ordinary Crossplane garbage collection — no separate teardown path.
4. A Kyverno policy validates, at `XEnvironment`-claim admission time, that every declared dependency has a
   matching, non-expired `ServiceGrant`, denying with an actionable message (naming the owning team and the
   grant path to create) if not.

### D4 — L7 HTTP scoping: a confirmed capability, not a speculative one

`capability.network.http` (optional method/path narrowing on top of L4 ports) is included as a v1 feature
because it was verified live, not assumed: `enable-l7-proxy` / `enable-envoy-config` / `external-envoy-proxy`
are all `true` in the `cilium-config` ConfigMap on both preprod and platform, and the `cilium-envoy` DaemonSet —
the component that actually performs HTTP method/path matching — is healthy on every node on both clusters
(Cilium v1.19.4). The caveat: **no CiliumNetworkPolicy on this platform currently uses an `http` rule** — the
capability is configured and healthy, but this is its first real exercise. Verification therefore has to prove
the narrowing actually blocks a disallowed path/method, not just that the allowed one works.

### D5 — Defense-in-depth on the `ServiceGrant` object itself

The git-level gate alone is not treated as sufficient authorization for something that grants cross-team
network access — the same reasoning that makes `restrict-environment-envelope` exist as an admission-time
backstop beyond the git gate for `XEnvironment` claims:

- **RBAC**: only the GitOps controller's identity (the same `exclude_principals`-style set already used for
  the Environment Composition's cluster-wide writes) may create or modify a `ServiceGrant` directly on the
  cluster; a bypassed or misconfigured git gate is not the only thing standing between "reviewed" and "live."
- **Regulated-tier exclusion by default**: a `ServiceGrant` is denied — both at the gitops-gate and, again, at
  Kyverno admission — if either `target` or `subject` resolves to a hipaa/pci-tier team or product. This
  mirrors the existing precedent set by the cross-team observability grants, which already exclude
  regulated-tier data from being grantable. Open it up only when a real regulated-tier cross-team need exists.
- **Fail-closed admission lookup**: the Kyverno `context.apiCall` that checks for a matching `ServiceGrant` is
  explicitly configured to **deny** if the lookup itself errors (an API hiccup, a timing gap during rollout).
  Kyverno's default is not automatically "deny" here, and leaving it implicit would let a transient failure
  silently wave through an ungranted cross-team dependency — backwards for a security check on a fail-safe-deny
  platform.

### D6 — Expiry is enforced, not just recorded

`expiresAt` is meaningless if nothing reads it. A periodic sweep (interval and exact mechanism — CronJob vs. an
existing operator pattern — decided at build time) lists `ServiceGrant` objects and deletes any past
`expiresAt`; Crossplane's existing ownership-based GC then removes both CNPs for free, with no new teardown
logic required. The sweep's ServiceAccount is scoped to exactly `list` + `delete` on `servicegrants`, and the
interval is chosen and documented as the accepted staleness window (the bound on how long an expired grant's
network access can remain live but unenforced), not left as an accident of whatever a CronJob schedule
defaults to.

## Consequences

### Positive

- Zero hand-authored cross-team CiliumNetworkPolicies going forward — the mechanism that caused the earlier
  tenant→platform-service incident is retired for every future cross-team integration.
- Cross-team network exposure becomes auditable in one place: every grant is a git object in
  `gitops/grants/<team>/`, reviewed by the producer team, admission-gated, and expirable.
- Gives [ADR-090](090-governance-identity-model.md)'s "workload-to-workload" layer classification a real
  mechanism, without disturbing `AccessGrant` or its human-RBAC consumers.
- `service-grant-api`'s Composition stays small and independently testable; the platform's largest existing
  Composition (`environment-api`) is untouched.
- L7 HTTP narrowing lets a grant scope down to the one action actually needed (e.g. `POST /shipments`) instead
  of opening an entire service — genuinely stronger than the L4-only precedent this replaces.

### Negative / Known gaps

Two gaps are consciously deferred rather than silently omitted:

- **No team-level kill switch.** There is no way for a team to opt out of ever being named as a `ServiceGrant`
  subject or target (analogous to how `envelope.resources.allowedEngines` already gates self-service cloud
  resources per team). Reasonable as a v2 addition once a real team wants it; building it speculatively now
  isn't justified.
- **No extra approval gate for `prod`-stage grants.** Prod promotions elsewhere on this platform get
  release-approver review; a `ServiceGrant` touching a `prod` stage gets nothing beyond normal PR review for
  now. The first real integration built on this primitive ships dev-stage-only; prod-specific gating is added
  when a real prod cross-team case exists, rather than guessing at the right gate shape in advance.

### Risks

- The Kyverno admission gate (`restrict-environment-dependencies`) ships Audit-first and only flips to Enforce
  once verified that no undeclared cross-team dependency exists today that it would retroactively break —
  standard additive-rollout posture, but worth calling out since a premature Enforce flip could break a live
  integration that predates this ADR.
- The expiry sweep is a new always-on component with cluster-wide `list`/`delete` on `servicegrants`; scoping
  its RBAC tightly (D6) is what keeps that surface small.

## Alternatives considered

- **Extend `AccessGrant` to also carry network capability.** Rejected (D1) — its `subject`/`posture` schema is
  built for human RBAC and doesn't fit a machine-to-machine network capability; overloading it would make both
  jobs worse.
- **Fold the reconciliation logic into the `environment-api` Composition.** Rejected (D2) — couples a small,
  additive capability to the platform's largest and most critical existing Composition for no shared benefit.
- **Leave cross-team CNPs hand-authored, just documented better.** Rejected — documentation doesn't prevent the
  two halves drifting out of sync; that's exactly the failure mode that already caused an incident.

## Related

- [ADR-068](068-product-scoped-and-cross-team-access-model.md) — the sibling grant vocabulary (`AccessGrant`);
  not edited by this ADR, but `ServiceGrant` deliberately mirrors its owner-authored, gitops-gated,
  admission-backstopped shape.
- [ADR-090](090-governance-identity-model.md) — the "workload-to-workload" machine-access layer classification
  this ADR finally gives a mechanism to.
- [ADR-057](057-service-identity-and-east-west-zero-trust.md) — the paired-CNP east-west model this ADR extends
  from cross-*namespace* to cross-*team*, and the source of the "both netpol halves" pattern `ServiceGrant`'s
  reconciler automates.
- [ADR-067](067-idp-domain-model.md) — the Product/Environment domain model; grants and dependencies are
  declared at Product/Environment granularity, reusing that model rather than inventing a new one.
