# Temporary-Power Activation Controller

The implementation design for the always-on activation controller of
[ADR-088](../adrs/088-temporary-power-activation.md) — the service that lets an eligible operator **borrow**
a dangerous power for a bounded window and **yank it back** in an emergency. This is the *design*; it is not
yet built. The eligibility read-side and the controller-down break-glass CLI (`platctl access
grant`/`revoke`) exist; this controller is the activation half ADR-088 deferred.

ADR-088 fixed the **what** (eligibility decided slowly in git; activation fast at a controller; self-service +
loud-and-reviewed break-glass; AWS slow-but-honest, cluster instant). This doc fixes the **how**: a
Kubernetes **operator** built with **Kubebuilder / controller-runtime**, fronted by a thin imperative API.

> **Status:** increment 1 BUILT (`operators/activation/`) — the `Activation` CRD + reconcile lifecycle + the
> AWS Identity Center plane + envtest/unit tests. The shape (operator, Kubebuilder, the `Activation` CRD, the
> API front edge) is decided — see [ADR-088](../adrs/088-temporary-power-activation.md). Field names and the
> per-plane details below are a starting contract that firmed up during the build.
>
> **Amendment (2026-06-28, increment-1 build): two corrections the build forced.**
> (1) **The AWS plane uses AWS SDK Go v2, not a shell-out seam.** The `platctl` CLI shells out to the `aws`
> binary; a long-running operator wants a distroless image, typed errors (`ConflictException` →
> requeue, not failure), and no process-spawn-per-poll, so the adapter is SDK-native. The pure-Go
> eligibility/cap logic (`access.PlanActivation`/`ParseSessionDuration`) is still the thing to reuse — that
> reuse lands with the (deferred) cap/eligibility increment, not here.
> (2) **Mint and revoke are ASYNCHRONOUS and polled.** `create`/`delete-account-assignment` return
> `IN_PROGRESS` and must be polled (`describe-…-status`) to terminal; AWS serializes them per permission set.
> So a single reconcile cannot complete a mint — the adapter drives a per-account state machine across many
> reconciles, one in-flight op at a time. (`platctl` is fire-and-forget here — it never polls — a latent
> serialization bug; a **platctl durable-fix follow-up**.) Revoke reads the live AWS footprint (USER
> assignments) as source of truth, never `status`, so a lost status write can't leak a grant.

## Why an operator (not a plain service)

The active-grant loop has a property that decides the architecture: **revoke must succeed reliably against a
flaky external system**. AWS Identity Center provisions assignments serially per permission set and throttles
(the race that bit the [#888](https://github.com/asanexample/platform/issues/888) cutover). Auto-expiry and the
kill-switch therefore need idempotent revoke, per-target partial-failure handling, and backoff — exactly what
controller-runtime's work-queue + `requeueAfter` + finalizers provide, and exactly what a hand-rolled
"check-every-30s" timer gets wrong. Three more forces point the same way:

- **The kill-switch wants finalizers.** "Revoke everything now" as `delete Activations --all` is crash-safe:
  a finalizer guarantees each native grant is torn down even if the controller restarts mid-panic. A bespoke
  service can partial-complete a revoke-all across a crash and lose the thread.
- **The portal sees CRs for free.** Backstage already runs the Kubernetes plugin; `Activation` CRs surface
  "who holds power right now" with no extra API or UI. (The front door *is* Backstage — ADR-088 D3.)
- **Multi-plane fan-out.** The real controller grants across AWS + Keycloak + cluster (Teleport). One CR → N
  native grants, each with its own status and retry, is cleaner than a handler firing three sequential calls
  and hoping. This is where the feature goes, not where it starts.

The one genuinely imperative concern — verifying a **fresh passkey step-up** at request time — is a
point-in-time check that doesn't fit reconcile. It lives in a thin **API in front of** the CRD, not in the
reconciler and not in an admission webhook (see [The API front edge](#the-api-front-edge)). That hybrid — an
imperative intake that creates a reconciled object — is the normal mature-operator shape (cert-manager's
`CertificateRequest`, etc.).

### Why Kubebuilder, and the rejected alternatives

- **Kubebuilder + controller-runtime** — the canonical, minimal scaffolding (kubernetes-sigs) over the
  controller-runtime engine: the manager, reconcile loop, work-queues with backoff, finalizers, leader
  election, informers, `controller-gen` (CRD + RBAC from code markers), and `envtest`. It is the grain the
  platform already runs on (Crossplane, cert-manager are controller-runtime lineage) and keeps us in **Go**,
  reusing today's `cmd/platctl/internal/access` (eligibility) and `internal/cloud/identitycenter` (mint/revoke)
  directly in the reconciler.
- **Operator SDK — rejected.** It is essentially *Kubebuilder + OLM + bundle/scorecard*; its Go path delegates
  to Kubebuilder. Its differentiators target **OperatorHub / OpenShift marketplace distribution**, which we do
  not do — we deliver via ArgoCD on our own hub. All net-new surface, zero benefit here.
- **"Just use Crossplane" — rejected.** Crossplane reconciles *declarative, git-desired* external resources —
  the exact path ADR-088 rejected for activation. It could handle the **mint** but obstructs everything that
  matters: TTL/auto-expiry is not a Crossplane concept (you'd still need a controller to delete the XR at
  `expiresAt`), step-up has no home in a Composition, the Keycloak/Teleport planes lack mature providers, and
  `provider-aws` coverage for `sso-admin` USER account-assignments is thin. It would own the easy 20% and fight
  the security-critical 80%.
- **A plain always-on service — rejected** (the close runner-up; see ADR-088 amendment). Loses finalizers,
  free portal visibility, and per-plane reconcile status; reinvents the retry/expiry machinery the #888 race
  proves we need. Its only edge — "ship the AWS slice faster" — is a sequencing argument, not an architecture
  one, and this is the *real long-term* system.

## Components

```text
   Backstage "Activate Power"                    Activation Controller (hub, Kubebuilder)
  ┌──────────────────────────┐   create CR     ┌──────────────────────────────────────────────┐
  │ pick power / reach /      │ ───────────────▶│  Activation CRD  (etcd = active desired state) │
  │ duration / reason         │   (API only)    │  Reconciler:                                   │
  │ → fresh passkey step-up   │                 │   • mint per plane on create (+finalizer)      │
  └─────────────┬────────────┘                  │   • requeueAfter → revoke at expiresAt         │
                │ POST /activate                 │   • periodic resync = drift backstop           │
                ▼                                │   • revoke-all = delete CRs (finalizers)       │
  ┌──────────────────────────┐  validate +      └───────┬───────────────┬──────────────┬─────────┘
  │  Activation API (intake)  │  create CR               │ AWS IdC       │ Keycloak     │ Teleport
  │  • eligibility (git)      │                          ▼ (now)         ▼ (later)       ▼ (later)
  │  • fresh step-up (OIDC)   │                    sso-admin assign    group/role      access req
  │  • duration ≤ role cap    │
  └──────────────────────────┘            append-only audit ─────────▶ ADR-084 Postgres (history)
```

- **Activation API (intake)** — a small authenticated HTTP service. It is the **only** principal allowed to
  *create* `Activation` CRs (RBAC), so a borrow cannot be minted by `kubectl apply` that skips step-up.
- **Activation CRD + reconciler** — the controller proper. The CR is the source of truth for *what is active
  now*; the reconciler makes the native systems match it and tears them down on expiry/delete.
- **Audit** — every transition (request, mint, expire, revoke, failure) appends to the ADR-084 directory
  Postgres. The CR is ephemeral (deleted on expiry); the Postgres log is the durable history and the
  governance-observability input (ADR-088 §3.6). **Two stores, two facts:** etcd = *active*, Postgres =
  *history* — not two sources of truth for the same fact.

## The `Activation` CRD

`apiVersion: platform.refplat.org/v1alpha1`, `kind: Activation`, **cluster-scoped**. (Name `Activation` over
`TemporaryGrant` — kubectl-friendly and matches ADR-088's vocabulary; final call at build.)

```yaml
apiVersion: platform.refplat.org/v1alpha1
kind: Activation
metadata:
  name: josh-break-glass-platform-7f3a    # <principal>-<role>-<reach>-<rand>
spec:
  principal: josh                          # Person.Name (= the IdC username, = Keycloak anchor's roster name)
  role: break-glass                        # WorkforceRole in gitops/roles
  reach:                                   # exactly one of:
    scope: platform                        #   platform-scoped, or
    # team: alpha                          #   team-scoped
  duration: 1h                             # requested; the controller caps to the role's sessionDuration
  reason: "prod incident #123"             # required (audit)
  requestedBy: josh                        # the authenticated requester (audit; usually == principal)
  stepUp:                                  # the RESULT of step-up, recorded by the API — never the token
    authTime: "2026-06-28T15:04:05Z"
    acr: "https://refplat.org/acr/passkey"
status:
  phase: Active                            # Pending | Active | Expiring | Expired | Revoked | Failed
  grantedAt: "2026-06-28T15:04:07Z"
  expiresAt: "2026-06-28T16:04:07Z"        # grantedAt + capped duration — AUTHORITATIVE for expiry
  planes:
    - name: aws-identity-center            # one entry per target plane
      state: Granted                       # Pending | Granted | Revoked | Failed
      detail: "PowerUserAccess on 829808296602, 620830101009, 554518885123"
  conditions: [ ... ]                      # standard Ready/Reconciling/Error conditions
```

Design notes:

- **`spec` is immutable after admission** (enforced by a validating webhook or the API). You don't *edit* a
  borrow — you let it expire or revoke it and request a new one. This keeps the audit trail honest.
- **`status.expiresAt` is the single source of truth for expiry**, set once at mint = `grantedAt + min(spec.duration, roleCap)`. Re-derived state on controller restart comes from here, so a crash never leaks a grant past its TTL.
- **`status.planes[]` carries per-plane state** so a partial cross-plane failure is visible and retried per
  target, not all-or-nothing.

## The API front edge

A borrow is created **only** through the intake API, which does what a reconciler can't:

1. **Authenticate** the caller (OIDC, Keycloak).
2. **Verify a fresh step-up** — the OIDC token's `acr` is the passkey level and `auth_time` is within a tight
   window (`max_age=0` semantics, ADR-088 D3 / the #885 `acr.loa.map` passkey seam). An already-open or hijacked
   session cannot borrow power.
3. **Check eligibility** against git (`gitops/people` × `gitops/roles`) — the same `Eligible()` decision the
   read-side and `platctl access check` expose.
4. **Cap the duration** to the role's `sessionDuration`.
5. **Create the `Activation` CR** with `spec.stepUp` recording the *result* of step-up (timestamps/acr), never
   the token (tokens are secrets and are not persisted).

RBAC makes the API's ServiceAccount the **sole** creator of `Activation` CRs; no human role can `create` one.
That is the security invariant: every active borrow provably passed step-up + eligibility, because the only
door that mints a CR is the one that checks them.

## Reconcile lifecycle

```text
 (CR created by API)
      │  add finalizer
      ▼
   Pending ──mint each plane──▶ Active ──(now ≥ expiresAt, or CR deleted)──▶ Expiring
      │ any plane Failed           │ requeueAfter = expiresAt − now              │ revoke each plane
      ▼                            │ periodic resync (drift backstop)            ▼  (idempotent, backoff)
    Failed (alert)                 ▼                                          remove finalizer → GC
                              portal shows it                              append Revoked/Expired to audit
```

- **Mint** (Pending → Active): for each plane in the role's projection, create the native grant idempotently;
  record `status.planes[].state`. AWS assignments are created **serially** (the #888 race). Failure on a plane
  → retry with backoff; persistent failure → `Failed` + alert (don't leave a half-grant silently).
- **Hold** (Active): `requeueAfter = expiresAt − now`. A periodic resync independent of the timer is the
  **drift backstop** (next section).
- **Expire / Revoke** (Active → Expiring → gone): triggered by the timer firing at `expiresAt` *or* by CR
  deletion (manual revoke / kill-switch). Revoke every plane idempotently, then remove the finalizer so the CR
  is GC'd. **Two acts** (ADR-088 §3.6): remove the native grant **and** invalidate live sessions (Keycloak
  logout-all; rely on short AWS session caps). Audit the revoke.
- **Crash-safety:** all durable state is the CR (`expiresAt`) + the Postgres audit. A restarted controller
  reconciles outstanding CRs — expired ones revoke immediately, live ones re-arm their timer. Nothing leaks.

## Drift backstop — power can't leak past its TTL

ADR-088 §3.3 invariant: **`live == standing(git) ∪ active(controller)`**. A periodic resync (not a watch — the
external systems aren't k8s objects, so even an operator polls) reconciles the live native grants against
`standing(git)` ∪ the set of `Active` `Activation` CRs, and **prunes anything in neither**. So if the
controller ever misses an expiry (bug, outage), the next resync rips out the leaked grant. `standing(git)` is
the same roster projection the #888/#889 generators emit; the controller reads it from git (or a generator-
published ConfigMap) so the two never disagree.

## Multi-plane projection

One role → potentially several native grants. The reconciler dispatches per plane; each plane is a small
adapter with `mint`/`revoke`/`reconcile`:

| Plane | Native grant | Status | Source of footprint |
|-------|--------------|--------|---------------------|
| **AWS Identity Center** | a USER account-assignment to the role's permission set on its accounts | **built** (increment 1; SDK Go v2, async-polled) | the permission set's live provisioned-accounts (no SOPS needed) |
| **Keycloak** | role's realm-role / group membership | later | `gitops/roles[*].keycloak` |
| **Cluster (Teleport)** | a Teleport access request / short role | later (ADR-088 D2: evaluate Teleport) | roles projected from `gitops/people` |

The AWS adapter is an **SDK-native reimplementation** of the behavior contract proven by
`cmd/platctl/internal/cloud/identitycenter.go` (study it for the API sequence; do not inherit its
fire-and-forget no-poll error handling — see the amendment), reusing the
`access.PlanActivation` eligibility/cap logic — built and live-verified read-side already.

## Credentials — the crown jewels (ADR-088 §3.3)

The controller can hand out master keys, so it is the apex thing to protect:

- **AWS:** runs on the hub with **EKS Pod Identity** assuming a role scoped to *only*
  `sso-admin:CreateAccountAssignment` / `DeleteAccountAssignment` / `Describe*` /
  `ListAccountsForProvisionedPermissionSet` on the activation permission sets — never broad admin. Prefer
  per-call short-lived federation over a standing connector identity where practical.
- **Keycloak:** a dedicated, narrowly-scoped service-account client (group/role management only) — **not** the
  master admin (which is now sealed; ADR-087).
- **The intake API and the reconciler are separate trust surfaces**; only the API mints CRs, only the
  reconciler holds the plane connector creds. Compromising the portal cannot directly mint native grants.
- The controller audits **its own** actions, not just the borrows.

## Delivery, testing, and the break-glass relationship

- **Delivery:** a platform-owned workload on the hub via the ADR-081/082 service road (the rails the triage
  agent runs on) — image built/signed through the shared supply chain, CRD + controller + API delivered by
  ArgoCD, observable in the LGTM stack, behind the internal gateway.
- **Testing:** `envtest` for the reconciler (Kubebuilder default), driven by an injected clock + a fake Plane
  so the async lifecycle and expiry are deterministic; the AWS adapter is unit-tested against a fake `API`
  that **models the async state machine** (`IN_PROGRESS`→poll→`SUCCEEDED`, `Conflict`, delete-`NotFound`).
- **`platctl` stays the recovery floor.** ADR-088: the controller is the *convenient* path; recovery must not
  depend on the thing whose outage is the emergency. `platctl access grant`/`revoke` (+ the IAM-user
  break-glass) remain the controller-down fallback **forever** — this operator never becomes a single point of
  failure for *recovery*, only for *convenient* activation.

## Engineering standards (non-negotiable)

This operator — and every operator/Go service the platform builds after it — is held to a high quality bar.
It hands out master keys; sloppiness here is a security defect, not just tech debt. The points below are
**illustrative of the standard, not an exhaustive checklist** — the bar is comprehensive, professional-grade
software engineering, and anything a competent reviewer would expect applies whether or not it is named here.
Each maps onto concrete structure:

- **Separation of concerns.** The intake API (authn + step-up + eligibility), the reconciler (lifecycle), the
  per-plane adapters (native mint/revoke), and the audit sink are **distinct packages with distinct
  responsibilities**. The API never touches AWS; an adapter never decides eligibility; the reconciler never
  parses an OIDC token. A change to step-up policy touches one package.
- **Single responsibility.** Each plane adapter does exactly one thing — reconcile *its* plane to the desired
  grant. Each reconcile pass advances one `Activation` toward its declared state. No god-objects, no
  "manager" that knows every plane's internals.
- **Decoupling via interfaces.** Planes sit behind a small `Plane` interface (`Mint`/`Revoke`/`Observe`); the
  reconciler depends on the interface, not on AWS/Keycloak/Teleport. The AWS plane's SDK calls sit behind a
  small fakeable `API` interface (the same decoupling discipline). New planes are added, not woven in.
- **Robust error handling.** Errors are **typed and wrapped** (`fmt.Errorf("…: %w")`, `errors.Is/As`), never
  swallowed and never `panic` in a reconcile path. Distinguish *retryable* (throttling, transient AWS) from
  *terminal* (eligibility revoked, malformed spec): retryable → requeue with backoff; terminal → `Failed` +
  alert. Partial cross-plane failure is **per-plane** state, never all-or-nothing.
- **Resilience / failure-tolerance.** Every native operation is **idempotent** (re-minting or re-revoking is
  safe) so retries and restarts can't corrupt state. Crash-safety comes from durable `status.expiresAt` +
  finalizers, not in-memory timers. The drift backstop is the last line: even a controller bug can't leak a
  grant past TTL. Assume AWS is flaky (it is — #888) and design for it.
- **Idiomatic Go, not sloppy.** `context.Context` threaded through every blocking call (already the `cloud`
  pattern); no global mutable state; small composable functions; accept interfaces, return structs; `gofmt` +
  `go vet` + `staticcheck` clean; `golangci-lint` in CI. No leftover `TODO`s in merged code, no dead code, no
  copy-paste-and-tweak — comments explain *why*, matching the surrounding house style.
- **Thorough, comprehensive testing.** Quality is *demonstrated by tests*, not asserted. Cover the **unhappy
  paths first** — they're where the danger is: a plane mint failing mid-fan-out, AWS throttling/partial
  failure, a controller crash-and-restart with grants outstanding, an expiry that races a manual revoke, a
  drift-backstop prune. Layers: **unit** (eligibility / cap / duration / each plane adapter against a fake) +
  **integration** (`envtest` for the full reconcile state machine: Pending→Active→Expiring→gone, finalizer
  teardown, requeue-at-expiry) + **end-to-end** against ephemeral/sandbox targets where feasible. The
  **security invariants are explicit test cases**, not assumptions: only the API SA can create an
  `Activation`; an expired grant *is* revoked; a borrow without fresh step-up is rejected; revoke is
  idempotent. Tests are **deterministic** (injected clock — already the `now time.Time` seam — no
  `time.Sleep`, no real wall-clock), run under `go test -race`, and zero-flake. Coverage is **meaningful**
  (the state machine and failure branches), not a number chased for its own sake.
- **Observability built in, not bolted on.** Structured logging (the controller-runtime `logr`/`zap` sink,
  leveled, with the `Activation` key on every line — never log a token or secret); **Prometheus metrics**
  (reconcile latency/errors, work-queue depth, mint/revoke success+failure per plane, a gauge of active
  grants, time-to-revoke); Kubernetes **Events** on the CR for human-visible transitions; traces where a
  request crosses the API→controller→plane boundary. A privileged action you can't see is a privileged action
  you can't govern (ADR-088 §3.6).
- **Security & least privilege end-to-end.** Least-priv RBAC + IAM (the scoped connector roles above);
  **validate and sanitize** every `spec` field at admission (CEL/OpenAPI + the API); **secure, fail-safe
  defaults** — on *any* uncertainty (eligibility unreadable, step-up unverifiable, plane unreachable) the
  answer is **deny / don't grant**, never fail-open; no secrets in logs, CR `status`, or events; signed
  images via the shared supply chain. Threat-model the component as the apex insider risk it is.
- **The CRD is a versioned public API — design it deliberately.** Start `v1alpha1`, evolve via real Kubernetes
  API conventions (additive changes, conversion webhooks if it graduates to `v1beta1`/`v1`, never a silent
  breaking change); a rich **OpenAPI schema + CEL validation** so bad specs are rejected at admission, not at
  reconcile; `status` carries standard `conditions`. Consumers (Backstage, the drift detector) depend on this
  contract.
- **Operational lifecycle & resource hygiene.** Graceful shutdown (drain in-flight reconciles, release the
  leader lock); health/readiness probes; honor `context` cancellation everywhere; no goroutine or connection
  leaks (`defer Close`, bounded concurrency); rate-limit/back-off external calls (cache reads via informers).
  Configuration is explicit (flags/env/CR), with sane defaults and **fail-fast on misconfiguration** at
  startup.

### High availability

HA is required, and it differs by plane:

- **Controller — active-*passive*, via controller-runtime leader election** (the framework built-in; on by
  default in Kubebuilder, backed by a `Lease`). Run ≥ 2 replicas; **one leader reconciles, the rest are warm
  standbys.** Active-active is deliberately *avoided* — two reconcilers racing one `Activation` would
  double-mint/revoke against the serial-SSO path. The ADR-085 mutate auto-injects the PDB + zone/node
  topology-spread, so replicas land across failure domains for free.
- **Intake API — active-active**, the normal stateless way: N replicas behind a Service, all serving. No
  leader election.
- **State rides existing HA:** active grants in etcd (the cluster's, already HA); audit in CNPG Postgres
  (its own HA, subject to the known CNPG backup/failover caveats in the backlog).
- **Failover is leak-safe, not instant.** On leader loss there is a lease-duration gap (~15s) with no
  reconcile — but all durable state is `status.expiresAt` + the CRs, so **nothing leaks**; auto-expiry pauses
  and catches up when a standby takes the lease.
- **The emergency guarantee is independence, not the controller's HA.** Per ADR-088, the recovery floor
  (`platctl access grant`/`revoke` + the IAM-user break-glass) has **no dependency on the controller**, so a
  total controller outage cannot block emergency revoke. Leader-election HA keeps the *convenient* path up;
  the *recovery* path is guaranteed by being out-of-band entirely.
- **Simplicity, maintainability, operability.** Prefer the simplest design that meets the need — YAGNI, least
  astonishment, readable over clever, no premature abstraction. Godoc on exported symbols and package docs;
  an operator **runbook** (debug a stuck `Activation`, use the kill-switch, read the audit trail); small,
  reviewable PRs with conventional commits. CI **gates** all of the above (fmt/vet/staticcheck/lint/test/race/
  coverage) so the bar is enforced by the pipeline, not by memory.

## Open questions (firm up at build)

- CRD kind name (`Activation` vs `TemporaryGrant`) and whether step-up is enforced by the API alone or also a
  validating webhook on `create`.
- Whether the audit log is Postgres-only or also mirrored to Loki for the governance dashboards.
- Per-call federated creds vs a scoped standing connector identity per plane (security vs operational
  simplicity).
- Teleport-vs-custom for the cluster plane (ADR-088 D2 leaves this an evaluation).

## Related

- [ADR-088](../adrs/088-temporary-power-activation.md) (the decision this implements)
- [identity-and-access-strategy](identity-and-access-strategy.md) §2.3 (power is temporary), §3.1 (step-up),
  §3.3 (connectors, the drift guardrail), §3.6 (emergency revocation, governance)
- [ADR-081](../adrs/081-platform-service-delivery.md) / [ADR-082](../adrs/082-platform-agent-runtime-xagent.md)
  (the service-delivery road), [ADR-084](../adrs/084-platform-identity-directory-and-owner-resolution.md) (the
  directory Postgres), [#885](https://github.com/asanexample/platform/issues/885) (the passkey step-up seam)
