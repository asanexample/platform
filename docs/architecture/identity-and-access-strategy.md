# Identity & Access Strategy (North Star)

**Status:** Strategy / direction — forward-looking. **Date:** 2026-06-27.

The *where we're going* companion to [identity-and-sso.md](identity-and-sso.md) (the *where we are*
explainer). It sets one unified picture for how every person and machine gets an identity and the right
access across every system the platform touches — today's (AWS, Kubernetes, ArgoCD, Backstage, Grafana)
and tomorrow's (GitHub, PagerDuty, Slack).

This is a **reference platform**: a goal in its own right is to **demonstrate solving identity & access at
scale**, even while we are tiny. So the document has two halves — **the model** (§2), which is
deliberately simple, and **designing for scale** (§3), which honestly owns the hard parts that emerge when
the model meets thousands of principals, many systems, autonomous agents, and a real org. The second half
is the point; a clean model that ignores the hard parts isn't a scale demonstration.

It **builds on** a deep existing body of decisions and **evolves** them where this newer thinking goes
further (the full reconciliation is §4). Where this doc and an older ADR disagree, this is the newer
thinking — the ADRs inform the direction, they don't dictate it. Decisions that harden here get written
back as ADR amendments or new ADRs.

## Contents

- **§1 Scope & principles** — what's in scope, and the rules everything else follows.
- **§2 The model** — planes, roles, temporary power, the git source of truth, projection.
- **§3 Designing for scale** — the hard parts, by layer, each with the design it forces.
- **§4 How this lands on the ADRs** · **§5 Roadmap** · **§6 Open questions**

---

## 1. Scope & principles

### Scope

- **In scope: workforce + machines.** The humans who build, run, and observe the platform and its apps,
  and the workloads/agents that act for them.
- **Deferred: customer/end-user identity (CIAM).** Named as a real future plane so today's decisions
  preserve the seam, but **not built now** (no external end-users yet; external blast radius; scope
  discipline). Keeps faith with ADR-068's own "Customer auth is a separate plane" call. See §2.7.

### Principles

> **The vision, in one line:** decide a principal's access once — as a function of who they are and what
> they're on — and let the platform derive and project it into every system automatically, handing out the
> dangerous parts only temporarily.

1. **Declare once, derive, project.** A governed declarative claim in git is the source of truth;
   controllers reconcile it into live state. Access is **derived** — `(who you are) × (what you own or are
   assigned) × (policy)` — not granted by hand.
2. **Native enforcement, not a central PDP.** The single source is compiled *outward* into OIDC claims +
   generated native config, because off-the-shelf tools (AWS, ArgoCD, GitHub, PagerDuty) decide internally
   from token claims; they will not call a central policy server. A runtime authorization engine
   (Cedar/OpenFGA) is reserved for **apps we build and control**. *(The one place this principle strains —
   composed cross-plane authority — is confronted in §3.5.)*
3. **Least privilege, and most power is temporary.** Standing access is the safe everyday minimum;
   dangerous breadth is checked out and auto-expires (§2.3).
4. **Isolated planes, explicit trust edges.** "Unified" means one control pattern over trust-isolated
   planes — not one identity pool. No ambient trust; short-lived tokens everywhere. *(How this holds up at
   scale: §3.5.)*
5. **Design for scale, prove at current scale.** Default to scale-shaped solutions; pair them with
   dogfooding at today's size so the demonstration is real, not theoretical — design for the 50, prove it
   on the 3.

---

## 2. The model

### 2.1 Three planes

| Plane | Who | Trust domain | Anchor |
|-------|-----|--------------|--------|
| **Operator** | Platform engineers, developers, business/viewer users, auditors | One realm; brokers a corporate IdP if present | Keycloak (IdP of record) |
| **Machine** | Workloads + agents | Per-workload, short-lived, no static keys | Pod Identity / cosign-OIDC / (future) SPIFFE |
| **Consumer** *(deferred)* | End-users of the *products we host* (CIAM) | **One isolated realm per Product** | Keycloak realm, vended per-Product |

The planes share machinery (same broker tech, same declare→derive→project pattern, same audit) but **zero
shared trust or data**. Only operator + machine are in current scope. The boundaries are a feature — but
**real work crosses them**, and those *seams* are a first-class design surface, treated in §3.5.

```text
                         ┌──────────────────────────┐
                         │   git source of truth     │   declare once
                         │   Teams · People · Grants │   (reviewed PRs)
                         └────────────┬──────────────┘
                  derive + project    │
        ┌──────────────┬──────────────┼───────────────┬───────────────┐
        ▼              ▼              ▼               ▼               ▼
   Identity Center  Keycloak       GitHub          PagerDuty       (next system)
   = AWS access     = app login    = repo access   = on-call
        └──────────────┴──────── OPERATOR plane ─────┴───────────────┘

   MACHINE plane:  Pod Identity / cosign-OIDC / SPIFFE  (workloads + agents)
   CONSUMER plane: a vended Keycloak realm PER hosted Product  (CIAM — deferred, seam preserved)
```

### 2.2 Roles — the reach × power grid

A role is the answer to two questions, **reach** (your team · org-wide · the platform plumbing) and
**power** (look · operate · change · manage-access):

|              | **look** | **operate** | **change\*** | **manage-access** |
|--------------|----------|-------------|--------------|-------------------|
| **own team** | member   | developer   | developer    | team-admin / lead |
| **org-wide** | viewer · auditor | platform-operator | — | access-admin |
| **platform** | auditor  | platform-operator | — | break-glass |

\* *Big changes go through a reviewed PR, not a standing login — so "change everything by hand" is
deliberately empty. Even senior engineers are powerful through git + approval, not a god-mode credential.*

The named starter set:

- **developer** — deploy + operate *their own team's* products; sees nothing outside the team.
- **team-admin / team-lead** — developer + governs the team's membership, grants, envelope; default holder
  of **release-approver** (gated prod, separation of duties — ADR-068 §7).
- **viewer** — read-only, **scope-adjustable** (one product for a business user, org-wide for an exec).
- **platform-operator** — org-wide *look + operate* for on-call/SRE; changes setup via git, not by hand.
- **auditor** — org-wide read including security/compliance surfaces; changes nothing.
- **access-admin** — runs the access system itself; deliberately separate (and the apex risk — §3.6).
- **break-glass** — full power, off by default, time-boxed, loudly audited.

**Cross-team / restricted access** is *not* a role — it's the explicit, owner-approved, expirable
`AccessGrant` (ADR-068 §1), so collaboration never means "drop them in another team's group."

> **The grid is a simplification.** It's two axes of a more-dimensional reality — `stage × tier`
> (ADR-040), time, and data sensitivity also bound access (`effective = min(grant, posture(stage,tier))`).
> It's the teaching frame, not the whole truth; keeping it *comprehensible* at scale is itself a control
> (§3.2). And **machines are not just another box** on it — agents are autonomous, injectable, delegating
> actors that need their own treatment (§3.4).

### 2.3 Power is temporary, not standing

- **Safe, everyday access → standing** (a developer on their own team is already low-blast-radius).
- **Dangerous, broad access → temporary** — org-wide operate, platform admin, break-glass are checked out,
  for a reason, auto-expiring.

Two things kept separate: **eligibility** (who *may ever* hold a powerful role — rare, lives in git,
PR-reviewed) and **activation** (checking it out now, for an hour — frequent, fast, self-expiring, *not*
in git: you don't PR at 2am, and git can't expire on a timer). The activation design is
[ADR-088](../adrs/088-temporary-power-activation.md); the `platctl access` command group (read/list/check
eligibility, plus a `grant`/`revoke` break-glass fallback for a controller outage) is the first slice.

```text
  need more  →  request (portal button / `platctl access` / Slack)
             →  risk gate:  low = auto-grant    medium = 1 approval    high = break-glass
             →  controller flips the role ON  (AWS IC assignment · EKS access entry · k8s RoleBinding)
             →  timer flips it OFF automatically       ← the one genuinely new moving part
             →  logged:  who · what · why · when  (pinned to the incident)
```

Design rule: **make the emergency path fast** (reads auto-grant, approvals one-tap, break-glass always
works for a lone operator), or people route around it. The new build is the activation controller + timer;
AWS sessions already expire, so it's a gate in front of *assuming* the role.

### 2.4 The source of truth — Teams, People, Grants

Three git registries, all authored by reviewed PR (the existing Gate):

- **`gitops/teams/*.yaml`** *(exists)* — the team: its group, envelope, ownership, `release-approver` set,
  on-call pointer, incident channel.
- **`gitops/people/*.yaml`** *(built, #886)* — who the humans are and their grants. People used to be
  hardcoded in two places (the Identity Center HCL **and** Keycloak config); the roster now unifies them,
  and both generators derive from it (#888/#889). The role catalog lives alongside in `gitops/roles/` (#887).
- **`AccessGrant`** *(designed, ADR-068; `gitops/grants/` registry projection built, authored grants +
  consumption pending)* — the explicit cross-team / restricted exceptions.

A **Person** carries identity + grants; a grant is `(role × scope)`, optionally `activation: on-demand`:

```yaml
# gitops/people/sarah-chen.yaml
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: sarah-chen }
spec:
  person: <keycloak-sub>          # the anchor — the canonical identity (ADR-084)
  grants:
    - { role: developer, team: alpha }                  # standing — everyday access
    - { role: viewer, scope: platform }                 # standing — read-only elsewhere
    - { role: platform-operator, scope: platform, activation: on-demand }   # eligible, not standing
```

**Access facts in git, identity handles in the directory.** The Person roster holds *which person, which
roles* — **no PII**, the person referenced by Keycloak anchor. The runtime directory (ADR-084, Postgres)
holds the **handles** (GitHub login, Slack id, PagerDuty id), **discovered** via one-click OAuth at
onboarding, tiered by trust. **Email is never a join key; person PII never lives in git.** They *compose*:
git says "Sarah is a developer on alpha"; the directory resolves her GitHub login; the provisioner adds
that login to `team-alpha`. The bootstrap wrinkle (can't push to GitHub before she's linked) is bridged by
ADR-084's `declared` tier — an optional bootstrap handle in the roster, upgraded to `proven` on self-link.

### 2.5 Authoring — Backstage templates (gated PRs)

People author the roster through **Backstage scaffolder templates** (same pattern as New-Product /
deprovision). A template **proposes, never grants**: a form generates the `gitops/people/<name>.yaml`
change and **opens a PR** — the gate's approval routing (team-lead for team grants, access-admin for
platform roles) authorizes it. Joiner/mover/leaver is symmetric. Form-time validation (team + role from
the registry) shifts errors left; Backstage RBAC scopes *who can see* the template. **Off the template
path:** *activation* of temporary power (fast controller action, §2.3) and *identity linking* (the OAuth
"Connect your accounts" flow). Backstage is the view + editor; git is the record.

### 2.6 Projection — the connector fan-out

Once the roster is in git, **adding a system is adding a connector** that consumes the **slice** it needs:

|             | AWS (IC) | apps (Keycloak) | GitHub | PagerDuty | Slack |
|-------------|----------|-----------------|--------|-----------|-------|
| developer   | team roles | team apps | team repo (write) | team on-call | team channel |
| team-admin  | + manage | + manage | maintainer | + schedule | + usergroup |
| viewer      | read     | read-only | — | — | — |
| platform-operator | broad (on-demand) | broad read | — | platform on-call | — |
| auditor     | read     | read | read (audit) | — | — |

- **AWS** — Identity Center permission sets + assignments, generated from the roster (`gitops/people` ×
  `gitops/roles`); the generator is wired (#888), so the HCL is no longer the source of truth and "add a
  person" to AWS console access is one PR. **Cluster**
  access is a *separate plane*: human kubectl goes **OIDC-native** (Keycloak as EKS OIDC IdP, ADR-068 §6 /
  [#364](https://github.com/asanexample/platform/issues/364)) — which is where the unbuilt per-team
  `DeveloperAccess` regression (**#647**) is resolved, *not* the Identity Center generator; IAM federation
  is retained only for break-glass.
- **Apps** — Keycloak OIDC claims → ArgoCD / Backstage / Grafana RBAC *(already reads the Team registry)*.
- **GitHub** — org-team **membership** (the `github-teams` module already makes the teams, ADR-072; this
  adds members). **PagerDuty** — rotation membership; on-call resolved live (ADR-084 §7). **Slack** —
  channel/usergroup membership.

**Payoff — joiner-mover-leaver for free:** add a person → one PR → access everywhere; remove the file → one
PR → gone everywhere. *(The crucial caveat at scale — this does not cross plane boundaries — is §3.5.)*

### 2.7 The consumer plane (CIAM) — deferred

**Not in current scope.** Named for coherence; not built (no external users yet; external blast radius).
**Seam preserved:** keep the consumer plane a *separate trust domain* — don't bake "one realm,
operator-only" assumptions into the workforce build. **Intended shape later:** vend customer identity as a
**paved-road capability per Product** (a per-Product realm + OIDC endpoints from a claim, so the tenant
developer never operates an IdP), `compliance_tier` driving isolation strength. The fork to settle *then*:
authn + coarse roles only *(lean)* vs. also fine-grained app authz (Cedar/OpenFGA). CIAM's harder
requirements (consent, GDPR erasure, residency, passkeys, abuse defense) are why it's its own effort.

---

## 3. Designing for scale — the hard parts

The model in §2 is the easy 40%. At scale the complexity doesn't vanish — it **relocates** into the
projection layer, the machine plane, the cross-plane seams, and the human governance; *those* are the real
engineering, and access programs fail in them **organizationally** more often than technically. This
section owns them honestly: each item pairs a **risk** with the **design it forces**.

**How this is grouped.** The subsections cluster each problem where it's most naturally understood — two
access *functions* (auth, authz), the projection *mechanism*, the machine *plane*, the *seams* between
planes, and the *governance* around all of it. This is pragmatic clustering, **not a strict taxonomy**:
the operator plane has no section of its own because its scale problems live in auth (§3.1), the authz
model (§3.2), and governance (§3.6) — and several concerns deliberately cut across clusters (noted below).

**Maturity tags are independent of phase** (which phase introduces each surface is in the roadmap, §5):

- **`[must]`** — non-negotiable *for its layer*; that layer can't be credibly shipped without it.
- **`[op]`** — operational; bites within months of the layer being in real use.
- **`[later]`** — named and deliberately deferred.

> **If you read only four things** — the items that actually gate a credible scale claim: **translation
> bugs are invisible to drift detection** (§3.3), **the agent-identity model is decided but its enforcement
> is deferred** (§3.4 / ADR-074's own gap), **machine access has no review loop, so its bounds must be
> allowlist-shaped** (§3.4), and **meta-governance — changing the model re-permissions thousands** (§3.6).
> The other items are real but mostly name-and-address; these are existential.

**Cross-cutting threads** (the price of clustering by layer — each appears in several places; read them as
threads, not isolated bullets): **revocation** (lag §3.3 · runaway agents §3.4 · cross-plane kill-switch
§3.5 · the emergency switch §3.6); **non-human credentials** (connectors §3.3 · workloads/agents §3.4);
**the "no central PDP" carve-outs** (the decide/apply applier §3.3 · ADR-074's trusted-boundary agent
enforcement §3.4); and **audit / attribution** (ephemeral machine identity §3.4 · reviews and governance
observability §3.6).

### 3.1 Authentication & sessions

- **Auth strength scales with role power `[must]`.** Authz says *what*; authn proves *it's you*, and the
  proof scales with the role. **Phishing-resistant MFA (passkeys/WebAuthn) is the default** (not SMS/email
  codes); **step-up at elevation** (a fresh factor at checkout, §2.3); short, role-scoped sessions;
  enforced in Keycloak flows (`acr` assurance) and **invariant across the IdP seam**. Harden recovery — no
  self-service reset for privileged accounts (recovery is the usual MFA backdoor). *(Partly landed: the
  passkey/WebAuthn flow + admin-plane hardening shipped, #885/#899, [ADR-087](../adrs/087-keycloak-admin-plane-hardening.md).)*
- **Session lifetime is a tuned dial `[op]`.** Short limits stolen-token damage; long rides out an IdP
  blip (§3.3). Set it consciously per role; privileged sessions shorter.

### 3.2 The authorization model

- **The grid is N-dimensional in disguise `[must]`.** `reach × power` is two axes of
  `reach × power × stage × tier × time`. Don't pretend the grid is the whole model; posture composes
  (`min(grant, stage×tier)`), and the extra dimensions are explicit, not emergent surprises.
- **Clean RBAC decays into exception-sprawl — and that kills reviews `[op]`.** At scale, real needs don't
  fit the catalog: you either deny (→ shadow access) or accrete grants until **nobody can reason about
  what a role grants**, at which point access reviews (§3.6) degrade to rubber-stamps. *Forces:* bias to
  groups, a **bounded, comprehensible role catalog**, `AccessGrant` (capped) as the *only* escape hatch,
  and active resistance to per-team custom roles. Comprehensibility is a control.
- **Ownership-derived access sits on volatile ground `[op]`.** "Access = what you own" assumes a stable
  ownership graph; at scale ownership is co-owned, matrixed, and reorg'd constantly, so access **silently
  shifts** when a product moves teams — possibly mid-incident. *Forces:* an "ownership moved, access
  shouldn't instantly follow" rule (grace window + notify), not an instantaneous derivation.

### 3.3 The projection layer (the real Tier-0 system)

- **Translation bugs are invisible to drift detection — needs a third guardrail `[must]`.** Drift checks
  *live config == git*; it does **not** check *git == intent*. A bug in a role→native-permission translator
  produces config that perfectly matches git and silently over-grants thousands. *Forces:* **intent-vs-
  effected verification** (policy testing that asserts "a developer cannot reach another team," run on
  every model change) — the missing guardrail.
- **Decide/apply split `[must]`.** The projection executes whatever git says with god-tier privilege — a
  confused deputy whose only check is PR review, the softest boundary (and softer at scale). *Forces:* a
  separate, minimal-privilege **applier** that enforces machine-checkable invariants (no wildcard, no
  cross-tenant, no platform-target, no self-escalation) *before* applying — so review isn't the sole
  thing between a bad merge and god access.
- **Drift detection & reconciliation `[op]`.** Continuously compare live access to git: detect-and-alert →
  **auto-prune** (the ArgoCD model, applied to access) where safe, with a **mass-delete guardrail** (don't
  prune when the source looks suspiciously empty). Close the side doors (no standing console-edit rights).
- **Revocation lag `[op]`.** Projection is eventually-consistent and rate-limited by downstream APIs; bulk
  revoke (team disbanded, firm offboarded) is slow exactly when speed matters. *Forces:* a prioritized,
  rate-limit-aware revoke path; the kill-switch (§3.6) for the acute single-principal case.
- **Control-plane resilience `[op]`.** Keycloak and the activation controller are SPOFs. **The emergency
  path must not depend on the system whose outage is the emergency** — break-glass routes through an
  independent door (AWS IAM, ADR-068 §6), never Keycloak. Make Keycloak HA, backed-up, rebuildable from
  git; **fail soft** (a blip blocks new logins; existing sessions persist).
- **Connector credentials are the crown jewels `[op]`.** The access-granting connectors can grant
  anything — compromise = total. *Forces:* no static keys (short-lived federated creds), each connector
  scoped to one system, owned + rotated, and ideally itself operating through scoped, time-boxed elevation
  rather than holding standing god-rights.

### 3.4 The machine plane — model decided (ADR-074), enforcement open

**The agent-identity model is already decided in
[ADR-074](../adrs/074-agentic-workloads-platform.md)** — three separate identities (workload identity /
tool-and-model grant / on-behalf-of delegation), `effective authority = intersection(agent grant, the
caller's scope)` enforced by **trusted boundary code, never the agent**, **attenuating** non-escalating
delegation, agents as ADR-068 subjects, a named human sponsor, a per-agent + global **kill-switch**, and
prompt-injection defense by **provenance separation** (signed system prompt vs. untrusted conversation) —
all on a **zero-infrastructure-privilege, propose-only** base. That base defuses the scariest framings: an
agent has near-zero standing authority and can never exceed the live caller. So the items below are *not*
"design the model" — they're its **open edges**, several of which ADR-074 flags itself.

**Propose-only is the *floor*, not the ceiling.** It's the safe tier-0 posture — but the platform's
ambition is a fully-featured agent developer platform where selected agents *act* (e.g. real-time alert
remediation), not only propose. Crucially, an autonomous remediation has **no live human caller**, so the
intersection-with-caller bound doesn't apply — safety then comes entirely from **machine-enforced bounds**:
a tight capability envelope + reversibility-as-license + action-time policy + circuit breakers + autonomy
*earned* through evaluation. That is not "remove the guardrails"; it is *moving* them from a
human-in-the-loop to bounds trustworthy enough to stand in.
**[ADR-086](../adrs/086-autonomous-agent-access.md)** sketches that graduated-autonomy access model — the
concrete build-out of the `auto-policy-gate` ADR-074 deferred.

- **Enforcement of the invariants is the real gap `[must]`.** ADR-074 *decides* the invariants
  (propose-only, no-bypass, zero-privilege, intersection/attenuation) but explicitly **defers the admission
  surface** that makes a violating agent un-admittable — *"the Kyverno surface is to be designed, or the
  invariants are only an intention."* *Forces:* that Kyverno/admission policy + the
  `auto-policy-gate` (the autonomous-action access model, sketched in
  [ADR-086](../adrs/086-autonomous-agent-access.md)); it rides the rebuild-gated AccessGrant, so "one access
  model" is target, not interim.
- **Ordinary-workload bounds: allowlist, not deny-set `[must]`.** Distinct from agents — non-agent
  workloads churn thousands/day with **no human review loop**, yet are bounded by ADR-041's
  `policyStatements` *deny-set*, a blocklist that doesn't scale safely. *Forces:* automatically-derived
  **allowlist** bounds from declared needs, since there's no re-attestation backstop.
- **Ephemeral attribution `[op]`.** The identity that touched a bucket at 3am no longer exists. *Forces:*
  recording the **genealogy** (ephemeral-id → workload → deployment → team → human sponsor) so any past
  machine action is attributable — a forensic requirement and a real observability build.
- **Runaway containment beyond the single agent `[op]`.** ADR-074 has a per-agent + global kill-switch; the
  open delta is **cascade** (killing an agent must revoke its sub-agents and delegated tokens) and the
  cross-plane correlation (§3.5).
- **Root-of-trust & multi-cloud `[later]`.** "No static keys" still bottoms out in *something* trusted; a
  compromised node is an identity-forgery factory. And Pod Identity (AWS-locked) ≠ SPIFFE (the cloud-neutral
  fabric, a major build) — the multi-cloud workload-identity story is a headline, not a slash.

### 3.5 The cross-plane seams — mostly bounded by ADR-074, with residuals

ADR-074's `effective authority = intersection(agent grant, live caller scope)` + zero-privilege already
**bounds** most cross-plane risk: an agent can't exceed the live human, and the enforcement point is the
**trusted boundary** (context + action + gate) — so principle 2 holds (there's no *central* PDP; the
boundary *is* the decision point). What remains are genuine residual edges:

- **Auth-strength doesn't follow the human into the agent `[must]`.** The intersection bounds *breadth*,
  but the human's MFA / step-up (§3.1) doesn't automatically gate the *agent's* actions. *Forces:* a
  decision on **step-up / re-confirmation at the delegation boundary** for high-impact actions (ADR-074's
  tiered human-gate partly supplies this — the auth-strength tie-in is the unspecified part).
- **Offboarding — mostly solved, with a residual `[op]`.** Because authority is `intersection(…, live
  human)`, offboarding a human **collapses** the intersection — the agent can no longer act for them.
  Residual: clean up **long-running agent sessions/tokens** minted before offboarding. *Forces:* tying the
  agent kill-switch (§3.4) to human-lifecycle events.
- **Trust-edge explosion `[op]`.** "Narrow edges, no ambient trust" → an unauditable N² mesh, or
  capitulation to broad ambient trust, as services/agents multiply. *Forces:* a systematic
  **trust-derivation fabric** (service-mesh / SPIFFE-based authz minting edges from identity + intent).
- **Isolation fights accountability `[op]`.** Plane isolation for trust fights cross-plane correlation for
  accountability (and forensics). *Forces:* a correlation fabric that answers "who is ultimately
  responsible" **without** becoming the ambient-trust backdoor — its operational face is the cross-plane
  kill-switch.
- **The deferred consumer seam is the most security-critical `[later]`.** The
  `consumer → machine → operator` path connects untrusted outsiders to internals; deferring CIAM deferred
  the design of the seam that matters most. *Forces:* deliberate seam discipline now so it isn't a
  retrofit later.

### 3.6 Governance & operations (where access programs actually die)

- **Meta-governance of the model `[must]`.** Changing a role definition **re-permissions thousands at
  once** — the highest-blast-radius change in the system. *Forces:* **policy CI/CD** for the model itself —
  blast-radius analysis ("this diff adds delete to 1,400 principals"), staging, **canary** rollout,
  instant rollback.
- **Watch the watchers `[must]`.** `access-admin` is the apex insider risk — they can grant anything.
  *Forces:* two-person control for model/policy changes, full audit of admin actions, rogue-admin
  detection, and SoD (grantor ≠ beneficiary).
- **Emergency revocation `[must]`.** The PR path is deliberately slow; a compromised account needs access
  gone *now*. Revocation is **two acts** — disable future logins **and** invalidate live sessions/tokens.
  One trusted person can pull it, loudly audited; act-now, reconcile-after. Extends cross-plane (§3.5) and
  to agents (§3.4); note it can't reach user-minted secondary creds (PATs, access keys) — those need short
  lifetimes and a credential inventory.
- **Access reviews `[op]`.** Standing access drifts; SOC2/ISO/HIPAA require recertification. Because access
  is git-declared, a review is a **diff against one list**, and git history is the audit trail. **TTLs
  auto-expire most grants**; a **staleness surface** flags the standing rest (using login/activation logs
  as evidence). Reviewer = the owner; revoke = delete the file.
- **Learnability is a security property `[op]`.** At scale, hundreds author access; **misconfig-from-
  misunderstanding is the #1 incident cause.** *Forces:* optimizing the model + the §2.5 authoring
  templates for correct use under cognitive load, not just elegance — elegance that needs expertise to
  wield safely becomes over-grants.
- **Bus factor / operational ownership `[op]`.** The most security-critical system needs a team, on-call,
  and runbooks. A single owner is the gap between *designed* for scale and *operable* at scale — designing
  the human operation is part of the scale demonstration.
- **Governance observability `[op]`.** "We do reviews" is a claim that needs assurance. *Forces:* metrics
  on the governance process itself — % reviewed on time, mean-time-to-revoke, grant-age distribution,
  break-glass frequency, mis-grants caught — or healthy is indistinguishable from decorative.
- **Migration / no-lockout cutover `[op]`.** From today's hand-maintained HCL + seed users to the roster by
  **dual-run → verify-parity → flip**, independent break-glass live throughout — never a big-bang.
- **Forkability tension `[later]`.** Deep bespoke integration fights the reference-platform
  mission (ADR-053's own "un-forkable" worry). *Forces:* keeping bespoke parts behind swappable seams so a
  fork can substitute.
- **External/B2B humans & compliance mapping `[later]`.** Contractors/partners/auditors get scoped,
  TTL'd guest access (reusing temporary-access machinery). Compliance work is **mapping** the controls the
  model already emits (least privilege, SoD, reviews, audit trail, MFA) to a framework's checkboxes +
  evidence-on-demand — not new mechanism.

---

## 4. How this lands on the existing decisions

| Existing | This strategy |
|----------|---------------|
| **053/059** Keycloak IdP-of-record, access-as-code, pluggable seam, *no* central PDP | **Kept wholesale** — the spine. (§3.5 flags the one cross-plane strain on "no PDP".) |
| **068** product-scoped model: groups=identity, roles=access, `AccessGrant`, OIDC cluster-auth, release-approver/team-admin | **Kept** as the workforce access model. **Extended** with the non-builder role catalog (§2.2) + the unified temporary-power model (§2.3). Its CIAM deferral is **kept** (§2.7). |
| **040** posture = stage×tier, break-glass | **Generalized** into eligibility-in-git + timed activation for *all* powerful roles (§2.3). |
| **084** identity directory: discovered handles, PagerDuty on-call, email-never-a-key, PII-never-in-git | **Kept** as the runtime resolution + handle store; **composed** with the declared Person roster (access in git, handles in the directory — §2.4). |
| **074** agentic-workloads — the agent-identity model (three identities, intersection-authority, attenuating delegation, kill-switch, propose-only) | **Owns the machine/agent plane.** This doc **defers to it** (§3.4/§3.5); the open work is ADR-074's own deferred *enforcement* (the admission surface), not a new model. |
| **072** GitHub org-team ownership; **039/041/047** k8s RBAC + Pod Identity | **Connectors** in the fan-out (§2.6) + the machine-plane base (§3.4). |

---

## 5. Roadmap

Workforce-first, sequenced by value-per-effort. **Hardening is not a later phase** — the `[must]` items in
§3 land *with* the phase that introduces their surface, not after.

1. **People roster + AWS & Keycloak generators** *(built — #886/#887/#888/#889)* — `gitops/people/` +
   `gitops/roles/`, with *both* Identity Center (AWS console access) **and** keycloak-config (app access)
   derived from it, retiring the hand-maintained HCL and the Keycloak seed-users so "add a person" is one
   PR. (Per-team *cluster* access — the #647 regression —
   is a separate plane, resolved by OIDC cluster auth, step 5 / #364.) Lands with: auth strength (§3.1),
   meta-governance + watch-the-watchers (§3.6), the intent-vs-effected guardrail + decide/apply split
   (§3.3). The minimal v1 that earns its keep.
2. **GitHub membership connector** — org-team membership from the roster (handles via the directory).
3. **Temporary-power front door** ([ADR-088](../adrs/088-temporary-power-activation.md)) — the activation
   controller + timer + risk gate; wrap break-glass first; emergency revocation alongside. (The read-only
   `platctl access` inspector + break-glass fallback is the first slice.)
4. **PagerDuty + Slack connectors** — rotation + channel/usergroup membership; live on-call.
5. **OIDC-native cluster auth** — Keycloak as EKS OIDC IdP (ADR-068 §6); retire IAM-federation kubectl.
6. **Machine-plane & seams hardening** — the §3.4/§3.5 `[must]` items: **enforcement of ADR-074's agent
   invariants** + the **graduated-autonomy access model** ([ADR-086](../adrs/086-autonomous-agent-access.md),
   extending ADR-074 — autonomous remediation under machine-enforced guardrails), allowlist workload bounds,
   and the cross-plane residuals (delegation step-up, kill-switch cascade). *The hardest, most
   differentiating work — the core of the scale demonstration.*

*(Out of this roadmap: the consumer plane / CIAM — a later, separately-scoped effort once real end-users
exist.)*

---

## 6. Open questions (the real forks)

1. **Agent autonomy & enforcement** — ADR-074 keeps agent authorization at the *trusted boundary* (so "no
   central PDP" holds) but defers the enforcement surface and the `auto-policy-gate`.
   [ADR-086](../adrs/086-autonomous-agent-access.md) sketches the graduated-autonomy model; the open **crux
   is the reversibility / blast-radius classification** that licenses an action for autonomous execution.
   *(Sketched; classification unsolved.)*
2. **Machine bounds** — automatically-derived allowlist vs. the current deny-set for workload access
   (§3.4)? *(Lean: allowlist, since there's no review loop.)*
3. **Declared vs. discovered handles** — does the Person roster carry bootstrap handles (the `declared`
   tier) to push-provision before self-link (§2.4)? *(Lean: optional declared bootstrap, upgraded on
   link.)*
4. **Approval routing** — route a mixed Person PR's approval by *what's changing* (team-lead vs.
   access-admin)? *(Lean: yes.)*
5. **Build vs. buy / forkability** — how much of the control plane to build (to demonstrate scale) vs. keep
   behind swappable seams for forkability (§3.6)? *(Lean: build the differentiating parts, seam the rest.)*
6. **(Deferred) CIAM scope** — authn-only vs. + fine-grained authz, *if and when* the consumer plane is
   built. *(Lean: authn standard, FGA opt-in.)*

## Related

- **Current state:** [identity-and-sso.md](identity-and-sso.md)
- **ADRs:** [053](../adrs/053-identity-and-cross-system-authorization-strategy.md) ·
  [059](../adrs/059-identity-topology-pluggable-idp-seam.md) ·
  [068](../adrs/068-product-scoped-and-cross-team-access-model.md) ·
  [040](../adrs/040-platform-engineer-access-model.md) ·
  [084](../adrs/084-platform-identity-directory-and-owner-resolution.md) ·
  [039](../adrs/039-per-team-developer-rbac.md) ·
  [049](../adrs/049-tenant-model-team-tenant-zone.md) ·
  [067](../adrs/067-idp-domain-model.md) · [072](../adrs/072-app-repo-naming-and-team-ownership.md) ·
  [074](../adrs/074-agentic-workloads-platform.md)
- **Source of truth:** the git-native `Team` CRs (`gitops/teams/`, ADR-063) + the `gitops/people/` roster
  and `gitops/roles/` catalog (#886/#887).
