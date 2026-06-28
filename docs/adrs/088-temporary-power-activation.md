# ADR-088: Temporary-Power Activation — just-in-time elevation & emergency revocation

**Status:** Proposed (design — 2026-06-27)

> **Amendment (2026-06-28): the controller's implementation shape is decided.** Decision 1 committed an
> "always-on controller" but left its shape open. It will be a **Kubernetes operator built with Kubebuilder /
> controller-runtime** — a cluster-scoped **`Activation` CRD** reconciled by a controller, fronted by a thin
> **imperative intake API** that verifies eligibility + a fresh passkey step-up and is the *only* principal
> allowed to create `Activation` CRs (so no borrow can skip step-up). The CR is the source of truth for what is
> *active now* (etcd); the append-only **audit** history goes to the ADR-084 Postgres. Auto-expiry, retries
> against the flaky serial-SSO mint path, the kill-switch, and the §3.3 drift backstop all ride
> controller-runtime's work-queue + `requeueAfter` + **finalizers** — the decisive reason to pick an operator
> over a hand-rolled service. **Rejected:** a plain always-on service (loses finalizers, free Backstage-plugin
> visibility, and per-plane reconcile status; reinvents the retry/expiry machinery the
> [#888](https://github.com/asanexample/platform/issues/888) race proves we need — its only edge, "ship
> faster," is sequencing not architecture); **Operator SDK** (= Kubebuilder + OLM/bundle machinery aimed at
> marketplace distribution we don't do); and **modelling activation in Crossplane** (built for declarative
> git-desired resources — the path this ADR rejected — so it owns the easy *mint* but fights TTL/expiry,
> step-up, and the non-AWS planes). Full design + the `Activation` CRD/API contract:
> [temporary-power-activation-controller](../architecture/temporary-power-activation-controller.md). `platctl
> access grant`/`revoke` remains the controller-down recovery floor (built; AWS-IdC plane; dry-run-verified).
>
> **Increment 1 BUILT (`operators/activation/`):** the `Activation` CRD + reconcile lifecycle + the AWS
> Identity Center plane + envtest/unit tests. Two build-forced corrections (detailed in the design doc): the
> AWS plane uses **AWS SDK Go v2** (not a shell-out seam), and mint/revoke are **asynchronous, polled, and
> serialized per permission set** — so a reconcile advances a per-account state machine across many passes,
> and revoke reads the live AWS footprint (not status) as source of truth. Deferred: the intake API + step-up,
> cap/eligibility source, audit sink, delivery, and the Keycloak/cluster planes.

## Context

The workforce access model splits power in two ([identity strategy §2.3](../architecture/identity-and-access-strategy.md)): **everyday access is standing** (held all the time — `developer`, `viewer`, `auditor`, your own team's *operate* in test environments), but **dangerous power is borrowed, not held**. The dangerous powers are the `on-demand` roles in the catalog ([#887](https://github.com/asanexample/platform/issues/887)):

- **`platform-operator`** — org-wide *operate*: poke the live system to fix it (restart/scale/debug workloads + AWS across all environments). The on-call key.
- **`break-glass`** — full admin including the access controls themselves. The real master key; off by default, time-boxed, loudly audited.
- **`prod-operate`** (a per-environment elevation, ADR-040/049) — a developer's standing access is *view* in prod; touching prod by hand is borrowed.

Phase 1 built the **eligibility** half: an `on-demand` grant in `gitops/people` ([#886](https://github.com/asanexample/platform/issues/886)) declares *who may borrow what*, and the Identity Center / Keycloak generators ([#888](https://github.com/asanexample/platform/issues/888)/[#889](https://github.com/asanexample/platform/issues/889)) **deliberately exclude** on-demand grants from the standing projection — so they're inert until activated. [#885](https://github.com/asanexample/platform/issues/885) laid the **step-up** seam (the `acr.loa.map` + a passkey login that can be re-prompted).

What's missing is the **activation** half: the mechanism to *borrow* an eligible role for a bounded window, and to *yank it back* in an emergency. This is P3 of the epic ([#884](https://github.com/asanexample/platform/issues/884): "temporary-power front door + emergency revocation").

## Decision

**Eligibility is decided slowly in git; activation happens fast at a controller.** Conflating the two is the trap — borrowing power cannot wait for PR → merge → apply (minutes) when the site is down at 3am.

1. **A custom activation controller** owns the fast path for the **AWS Identity Center + Keycloak** planes — it reads eligibility from git, verifies a fresh step-up, mints the temporary native grant, runs the TTL timer, and exposes the kill-switch. It is the [#888](https://github.com/asanexample/platform/issues/888)/[#889](https://github.com/asanexample/platform/issues/889) generators' **imperative, temporary cousin**: same target systems and same git-eligibility source, but triggered by a click (not a PR) and reversed by a timer (not forever).

2. **The cluster (kubectl) plane evaluates [Teleport](https://goteleport.com/) rather than reinventing** session-recording + just-in-time RBAC. Git stays the single eligibility source either way (Teleport roles/requests are projected from `gitops/people`).

3. **The front door is Backstage** — an "Activate Power" plugin + a backend scaffolder-style action (reusing the onboard/offboard custom-action pattern, [#890](https://github.com/asanexample/platform/issues/890)). It requires **step-up**: an OIDC request with `max_age=0` / `acr_values` forcing a *fresh* passkey, so an already-open (or hijacked) session can't borrow power on your behalf.

4. **Activation is self-service** — eligibility-in-git **is** the approval, so `platform-operator` / `prod-operate` are instant self-service (no synchronous human gate when the emergency is exactly when you can't wait for one). **`break-glass` needs no synchronous approval either**, but it pings a security channel **loudly** the instant it's grabbed and forces a **mandatory after-action review**. Act-now, reconcile-after.

5. **Cluster is instant; AWS-console elevation is slow-but-honest.** AWS Identity Center provisions assignments **serially per permission set** (~tens of seconds, the race that bit the [#888](https://github.com/asanexample/platform/issues/888) cutover), so the AWS path shows an honest *"provisioning…"* progress UI. We explicitly **reject pre-staging** (creating the assignment disabled and toggling it) — it leaves a standing-but-off artifact that becomes a new thing to guard, not worth shaving ~20s off a rare action.

6. **Scope:** demonstration-scale (the sample roster) but **built to the standard a real team would rely on** — the full borrow → expire → revoke loop, no shortcuts.

## The design

### The activation flow

1. **Request** (Backstage) → pick a power you're eligible for, a target/scope, a duration (capped per role), and a **reason** (required).
2. **Step-up** → fresh passkey tap (re-auth, not the existing session).
3. **Controller** verifies: eligibility (reads `gitops/people` + `AccessGrant` from git, exactly as the generators do), the step-up token's `acr`/`auth_time` freshness, and the requested duration ≤ the role's cap.
4. **Mint** → the controller writes the temporary native grant (IC account-assignment / Keycloak group membership / Teleport access request) and records `{principal, role, scope, reason, grantedAt, expiresAt}` in a durable store.
5. **Expire** → a reconcile loop removes the grant at `expiresAt`. Crash-safe: state is durable, so a controller restart reconciles outstanding grants rather than leaking them.

### State + audit store

Reuse the **ADR-084 directory Postgres** for the active-grant table + the append-only audit trail (who/what/when/why/how-long, every grant + revoke). The audit trail is the governance-observability input ([§3.6](../architecture/identity-and-access-strategy.md)).

### Emergency revocation — the kill-switch

The controller owns it: **per-grant revoke** and **revoke-all** (compromised-account panic button). Revocation is **two acts** ([§3.6](../architecture/identity-and-access-strategy.md)): remove the native grant **and** invalidate the principal's live sessions/tokens (Keycloak logout-all + short AWS session caps), so an already-issued token doesn't outlive the revoke.

### Drift-detection coordination — power can't leak past its TTL

Standing drift detection compares *live == git*; the controller's temporary grants would look like drift and get pruned mid-window. So the rule is **`live == standing(git) ∪ active(controller store)`** — the drift detector treats active grants as authorized, **and is the backstop**: anything live that is neither in git *nor* in the active store gets pruned. So even if the controller dies and misses an expiry, the backstop rips the leaked grant out. This is the third guardrail from [§3.3](../architecture/identity-and-access-strategy.md) ("translation bugs are invisible to drift detection") applied to time.

### The controller's credentials are the crown jewels

The controller can hand out master keys, so it is the apex thing to protect ([§3.3](../architecture/identity-and-access-strategy.md) "connector credentials"). *Forces:* short-lived **federated** creds per plane (no static keys), each connector **scoped** to "add/remove these specific grants" (never broad admin), full audit of the controller's own actions, and — ideally — the controller operating through its *own* scoped, time-boxed elevation rather than holding standing god-rights. It runs as a platform-owned workload on the hub via the established service road (ADR-082/081, the same rails as the triage agent).

### break-glass must not depend on the system it recovers

[§3.6](../architecture/identity-and-access-strategy.md) / ADR-040: the emergency path can't route through the thing whose outage is the emergency. So the controller is the *convenient* break-glass path, but the **ultimate** fallback stays independent — the `OrganizationAccountAccessRole` / the management IAM-user (proved itself during the #888 cutover), plus a **`platctl grant`/`revoke`** manual command for when the controller service itself is down. The controller is a single point of failure for *convenient* activation, never for *recovery*.

### Why not platctl as the controller

`platctl` is an operator CLI that runs on a laptop and exits — it cannot run the TTL timer or answer "revoke now" unattended. Auto-expiry *requires* an always-on service. `platctl` gets only the controller-down break-glass `grant`/`revoke` fallback above.

## Consequences

- The genuinely dangerous powers (`platform-operator`, `break-glass`, `prod-operate`) **stop sitting in anyone's pocket** — they live in a logged controller, borrowed for the rare window they're truly needed, gone on their own. The standing attack surface shrinks from "always" to "the rare active window."
- A new **always-on, crown-jewel service** enters the trust center — the apex thing to secure and the apex single-point-of-failure for *convenient* activation (recovery stays independent).
- The cluster path feels instant; AWS-console elevation takes ~tens of seconds with an honest UI.
- `break-glass` is fast (no wait) but **loud + reviewed-after** — a deliberate trade of synchronous control for incident speed.

## Alternatives considered

- **Build all three planes custom (incl. cluster JIT + session recording).** Maximally on-philosophy, but reinvents what Teleport does well for kubectl. Rejected in favor of the hybrid.
- **Buy a full JIT/PAM product for everything.** Fastest, but pulls a large dependency into the trust center and is less git-native (the eligibility source-of-truth would drift out of `gitops/people`). Rejected; Teleport for the cluster plane only is the bounded version.
- **Pre-stage AWS assignments (disabled) and toggle.** Makes AWS instant, but leaves standing-but-off grants to guard. Rejected (see Decision 5).
- **Activation via a short-lived git `AccessGrant` (PR + apply).** Fully git-native and auditable, but PR → merge → apply is minutes — far too slow for incident response, and inherits the revocation-lag problem. Rejected for the *activation* path; git stays the *eligibility* path.
- **Synchronous peer-approval at borrow-time.** Stronger separation-of-duties, but defeats the 3am-incident speed the feature exists for; nobody may be around to approve mid-emergency. Rejected in favor of eligibility-as-approval + loud audit + after-action review.

## Deferred

- **Real on-call wiring (P4)** — PagerDuty rotation as an eligibility input ("you're on-call → eligible to activate"), live Slack/PagerDuty integration. This ADR is demonstration-scale.
- **Reversibility / blast-radius classification** — reuse [ADR-086](086-autonomous-agent-access.md)'s machine-action classification for *human* borrowing (higher-blast-radius power → shorter TTL / tighter step-up). Named, not yet specified here.
- **Fast AWS via pre-staging** — revisit only if AWS-console elevation latency proves painful in practice.

## Related

- [identity-and-access-strategy](../architecture/identity-and-access-strategy.md) §2.3 (power is temporary), §3.1 (step-up), §3.3 (connectors, the third guardrail), §3.6 (emergency revocation, governance)
- [#884](https://github.com/asanexample/platform/issues/884) (epic), [#885](https://github.com/asanexample/platform/issues/885) (passkey + `acr` step-up seam), [#886](https://github.com/asanexample/platform/issues/886)/[#887](https://github.com/asanexample/platform/issues/887) (roster + `on-demand` roles), [#888](https://github.com/asanexample/platform/issues/888)/[#889](https://github.com/asanexample/platform/issues/889) (the generators this controller mirrors), [#890](https://github.com/asanexample/platform/issues/890) (the Backstage action pattern)
- [ADR-040](040-platform-engineer-access-model.md) (break-glass + posture), [ADR-068](068-product-scoped-and-cross-team-access-model.md) (`AccessGrant` + `expiresAt`), [ADR-082](082-platform-agent-runtime-xagent.md)/[ADR-081](081-platform-service-delivery.md) (the platform-service road), [ADR-084](084-platform-identity-directory-and-owner-resolution.md) (the directory Postgres), [ADR-086](086-autonomous-agent-access.md) (the machine analogue of borrowed power)
