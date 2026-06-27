# Identity & Access Strategy (North Star)

**Status:** Strategy / direction — forward-looking. **Date:** 2026-06-27.

This is the *where we're going* companion to [identity-and-sso.md](identity-and-sso.md) (the *where we
are* explainer). It sets a single, unified picture for how **every** person, machine, and end-user gets
an identity and the right access across **every** system the platform touches — today's (AWS, Kubernetes,
ArgoCD, Backstage, Grafana) and tomorrow's (GitHub, PagerDuty, Slack, the products we host).

It **builds on** a deep existing body of decisions — Keycloak as the IdP of record and access-as-code
([ADR-053](../adrs/053-identity-and-cross-system-authorization-strategy.md)/[059](../adrs/059-identity-topology-pluggable-idp-seam.md)),
the product-scoped access model ([ADR-068](../adrs/068-product-scoped-and-cross-team-access-model.md)),
posture = stage×tier + break-glass ([ADR-040](../adrs/040-platform-engineer-access-model.md)), and the
platform identity directory ([ADR-084](../adrs/084-platform-identity-directory-and-owner-resolution.md)).
This strategy is **workforce-first**: it covers the humans (and machines) who build, run, and observe the
platform and the apps on it. **Customer/end-user identity (CIAM) is deliberately deferred** — named as a
future plane so today's decisions preserve the seam, but explicitly *not* in the current build (which keeps
faith with ADR-068's own "Customer auth is a separate plane" call). Within that scope it **evolves** the
prior decisions in two places, called out below: it names the **full workforce role catalog** (the ADRs
are developer-centric) and unifies break-glass + grant-expiry into **one temporary-power model**. Where
this doc and an older ADR disagree, this doc is the newer thinking — the ADRs informed the direction, they
don't dictate it. Decisions that harden here will be written back as ADR amendments or new ADRs.

---

## The vision in one line

> **Decide a principal's access once — as a function of who they are and what they're on — and let the
> platform derive and project it into every system automatically, handing out the dangerous parts only
> temporarily.**

Everything below is that sentence, unpacked.

## The organizing principle: declare once, derive, project

We already run the whole platform this way: a governed declarative claim in git is the source of truth,
and controllers reconcile it into live state (Environments, policies, delivery). Identity & access is the
same pattern applied to *people*:

- **Access is not granted by hand, it's *derived*** — a pure function of `(who you are) × (what you own
  or are assigned) × (policy)`. Membership in a Team, or an explicit grant, *is* the entitlement.
- **It's *projected* automatically** into each system's **native** enforcement — not adjudicated by a
  central runtime engine. This is ADR-053's deliberate choice: a single declarative source compiled
  *outward* into OIDC claims + generated native config, because off-the-shelf tools (AWS, ArgoCD,
  Grafana, GitHub, PagerDuty) decide internally from token claims and their own config; they will not
  call a central policy server. A runtime authorization engine (Cedar/OpenFGA) is reserved for **apps we
  build and control** (see *Consumer plane* below), not the fleet.

## Three planes, one control plane

"Unified" does **not** mean one identity pool for everyone. It means **one control pattern operating three
trust-isolated planes.** The boundaries between them are a feature — explicit, narrow trust edges, no
ambient trust, short-lived tokens everywhere.

| Plane | Who | Trust domain | Anchor |
|-------|-----|--------------|--------|
| **Operator** | Platform engineers, developers, business/viewer users, auditors | One realm; brokers a corporate IdP if present | Keycloak (IdP of record) |
| **Machine** | Workloads + agents | Per-workload, short-lived, no static keys | Pod Identity / cosign-OIDC / (future) SPIFFE |
| **Consumer** *(deferred)* | End-users of the *products we host* (CIAM) | **One isolated realm per Product** | Keycloak realm, vended per-Product |

The operator and consumer planes share machinery (same broker tech, same declare→derive→project pattern,
same audit) but **zero shared trust or data**. A tenant's customers can never see operators or each other.
**Only the operator and machine planes are in current scope** — the consumer plane is named here for
coherence and seam-preservation (see *The consumer plane — deferred*, below), not built.

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

---

## The role model — every "user class" is a box on a grid

Don't maintain a flat list of job titles that grows forever. A role is the answer to **two questions**:

1. **Reach** — *your own team* · *all teams (org-wide)* · *the platform plumbing*
2. **Power** — *look* · *operate* (restart/scale/rerun/read) · *change* (deploy/alter setup) · *manage
   access* (hand roles to others)

|              | **look** | **operate** | **change\*** | **manage-access** |
|--------------|----------|-------------|--------------|-------------------|
| **own team** | member   | developer   | developer    | team-admin / lead |
| **org-wide** | viewer · auditor | platform-operator | — | access-admin |
| **platform** | auditor  | platform-operator | — | break-glass |

\* *Big changes happen through a reviewed PR, not a standing login — so "change everything by hand" is
deliberately empty. Even senior engineers are powerful through git + approval, not a god-mode credential.*

**The named starter set:**

- **developer** — deploy + operate *their own team's* products; sees nothing outside the team. (ADR-068:
  team membership implicitly grants all the team's products at owner posture.)
- **team-admin / team-lead** — developer + governs the team's membership, grants, and envelope; default
  holder of **release-approver** (gated prod, separation of duties — ADR-068 §7).
- **viewer** — read-only; **scope-adjustable** (one product for a business user, org-wide for an exec).
  *This is the "business user" slot the current model doesn't name.*
- **platform-operator** — org-wide *look + operate* for on-call/SRE; still changes setup via git, not by
  hand. (Today's `PlatformAdmin`, ADR-040, refined.)
- **auditor** — org-wide read including security/compliance surfaces; changes nothing.
- **access-admin** — runs the access system itself (who gets which role); deliberately separate.
- **break-glass** — full power, off by default, time-boxed, loudly audited (ADR-040).

**Cross-team / restricted access** is *not* a role — it's the explicit, owner-approved, expirable
`AccessGrant` object (ADR-068 §1), so collaboration never means "drop them in another team's group and
over-grant everything."

**Machines reuse this same grid** — an agent is a non-human principal assigned a box (the triage agent is
*operate · org-wide · read-only*). No separate taxonomy.

> **Evolution note.** ADR-068 names developer / team-admin / release-approver / platform-admin /
> break-glass — the *building-and-shipping* roles. This grid keeps all of them and adds the
> **non-builder** classes (viewer/business, auditor, access-admin) and the explicit *reach × power*
> framing, so a business user or an auditor has a first-class home.

---

## Power is temporary, not standing

The split that makes this modern and safe:

- **Safe, everyday access → standing.** A developer scoped to their own team is already low-blast-radius
  (least privilege + isolation). Leave it on.
- **Dangerous, broad access → temporary.** Org-wide operate, platform admin, break-glass — *checked out*,
  for a reason, auto-expiring.

Two different things people conflate, kept separate:

- **Eligibility** (who *may ever* hold a powerful role) — changes rarely, lives in **git**, reviewed by
  PR. Slow on purpose.
- **Activation** (checking it out *right now* for an hour) — frequent, fast, self-expiring. Does **not**
  live in git (you don't PR at 2am; git can't expire on a timer).

**The front door — a dial, not a switch:**

```text
  need more  →  request (portal button / `platctl elevate` / Slack)
             →  risk gate:  low = auto-grant    medium = 1 approval    high = break-glass
             →  controller flips the role ON  (AWS IC assignment · EKS access entry · k8s RoleBinding)
             →  timer flips it OFF automatically       ← the one genuinely new moving part
             →  logged:  who · what · why · when  (pinned to the incident)
```

Design rule: **make the emergency path fast** (reads auto-grant, approvals one-tap, break-glass always
works for a lone operator), or people route around it.

> **Evolution note.** The pieces exist but aren't unified: ADR-040 gives break-glass + "prod is `view`
> for everyone, mutate only via gated PR"; ADR-068's `AccessGrant` already carries `expiresAt`. This doc
> names the **general model** — *every* powerful role is eligibility-in-git + timed activation — of which
> break-glass and the expirable grant are two instances. The new build is the **activation controller +
> timer**; AWS sessions already expire on their own, so it's a gate in front of assuming the role.

---

## The source of truth: Teams + People + Grants

Three git registries, all authored by reviewed PR (the existing Gate):

- **`gitops/teams/*.yaml`** *(exists)* — defines the team: its group, envelope, ownership, the
  `release-approver` set, on-call pointer, incident channel. *Defines the group and what it can do.*
- **`gitops/people/*.yaml`** *(new — the missing piece)* — who the humans are and their grants. *Says who
  is in which group and at what class.* Today people are hardcoded in two places (the Identity Center HCL
  **and** the Keycloak config); this unifies them.
- **`AccessGrant`** *(designed, ADR-068)* — the explicit cross-team / restricted exceptions.

A **Person** record carries identity + grants; a grant is `(role × scope)`, optionally `activation:
on-demand` for the temporary ones:

```yaml
# gitops/people/sarah-chen.yaml
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: sarah-chen }
spec:
  person: <keycloak-sub>          # the anchor — the canonical identity (ADR-084)
  grants:
    - { role: developer, team: alpha }                  # standing — her everyday access
    - { role: viewer, scope: platform }                 # standing — read-only elsewhere
    - { role: platform-operator, scope: platform, activation: on-demand }   # eligible, not standing
```

### Where identity *handles* live — declared access vs. discovered identity

This is the one place to be careful, and it's where this doc reconciles the provisioning goal with
ADR-084. There are **two different jobs**, and they belong in two different places:

- **Access facts → git** (the Person roster): *which person, which teams/roles/grants.* No PII. This is
  what drives **provisioning** (AWS roles, app access, GitHub-team membership, PagerDuty-rotation
  membership). The person is referenced by their **Keycloak anchor**, not by a pile of hand-typed handles.
- **Identity handles → the runtime directory** (ADR-084, Postgres): *the same human's GitHub login, Slack
  user-id, PagerDuty id.* **Discovered**, not declared — a person links them with one-click OAuth at
  onboarding ("Connect your accounts"); Keycloak brokers GitHub/Slack/PagerDuty and the directory syncs
  the federated identities, tiered by trust (authoritative / proven / declared). **Email is never a join
  key. Person PII never lives in git.**

**They compose** — and that composition is what delivers multi-system provisioning *without* putting PII
in git: the git roster says *"Sarah is a developer on alpha"*; the directory resolves *"Sarah's GitHub is
`schen`, her PagerDuty id is `P…`"*; the provisioner adds that login to the `team-alpha` GitHub team and
that id to alpha's rotation.

The one wrinkle to decide (see *Open questions*): on free GitHub/Slack tiers you can't push someone into a
team **before** they've linked. The clean bridge is ADR-084's existing **`declared` tier** — the Person
roster *may* carry an optional bootstrap handle that seeds provisioning at lowest trust, which the
directory **upgrades** to `proven`/`authoritative` when the person self-links — a declared handle seeds
bootstrap provisioning, and the OAuth link then verifies and upgrades it. Paid SCIM/SAML later makes it
zero-touch with no redesign.

### Authoring UX — Backstage templates (gated PRs)

People author the roster through **Backstage scaffolder templates**, the same pattern as the New-Product /
deprovision-Product scaffolders (and the access-grant template ADR-068 §8 already plans). A template
**proposes, never grants**: a form (person, team, role) generates the `gitops/people/<name>.yaml` change
and **opens a PR** — the gate's approval routing (team-lead for team grants, access-admin for platform
roles) is what actually authorizes it. Joiner / mover / leaver is symmetric — an offboarding template opens
a PR *removing* the file. Form-time validation (team from the registry, role from the catalog, extra
justification for `platform-admin`) shifts errors left, and Backstage RBAC (#197) scopes *who can see* the
template so it isn't a "make me admin" form for everyone.

**Two things stay off the template path:** *activation* of temporary power (the JIT checkout is a fast,
expiring action against the access controller — a PR is too slow for an incident) and *identity linking*
(the GitHub / Slack / PagerDuty "Connect your accounts" OAuth flow, ADR-084). Backstage is the **view +
editor** over git; git stays the source of truth (ADR-084: the portal is the human view, not the record).

---

## The projection fan-out — every system is just another connector

Once the roster lives in git, **adding a system is adding a connector** that consumes the **slice** it
needs. The role decides which systems a person even lands in — least-privilege per system:

|             | AWS (IC) | apps (Keycloak) | GitHub | PagerDuty | Slack |
|-------------|----------|-----------------|--------|-----------|-------|
| developer   | team roles | team apps | team repo (write) | team on-call | team channel |
| team-admin  | + manage | + manage | maintainer | + schedule | + usergroup |
| viewer      | read     | read-only | — | — | — |
| platform-operator | broad (on-demand) | broad read | — | platform on-call | — |
| auditor     | read     | read | read (audit) | — | — |

- **AWS** — Identity Center permission sets + group assignments, **generated from the registry** (today
  hand-maintained HCL — the real gap; this also closes the unbuilt per-team `DeveloperAccess` role, #647).
  Human kubectl goes **OIDC-native** (Keycloak as EKS OIDC IdP, ADR-068 §6); IAM federation retained only
  for break-glass.
- **Apps** — Keycloak OIDC `groups`/`roles` claims → ArgoCD / Backstage / Grafana native RBAC *(already
  reads the Team registry)*.
- **GitHub** — org-team membership. The `github-teams` module already creates the teams from the registry
  (ADR-072); the missing piece is **membership** (one more Terraform resource, keyed on the resolved
  handle). *Easy — you're halfway there.*
- **PagerDuty** — user + rotation membership for on-call-capable roles. The registry holds a **pointer**
  (`pagerduty.escalationPolicyId`), and on-call is resolved **live** from PagerDuty (system of record,
  ADR-084 §7), not hardcoded.
- **Slack** — channel / usergroup membership; the `slackId` comes from the directory.

**The payoff — joiner-mover-leaver for free.** Add a person → one PR → access appears everywhere. Remove
the Person file → one PR → they're gone from AWS, the clusters, every GitHub team, and PagerDuty at once.
The always-forgotten offboarding step becomes atomic — the thing big shops pay SailPoint/Okta Lifecycle
for, as a side effect of the design.

---

## The consumer plane (CIAM) — deferred

**Not in current scope.** Customer/end-user identity is named as a real plane for architectural coherence,
but we are **not building it now** — there are no external end-users yet, its blast radius is *external*
(privacy regulation, breach liability on behalf of tenants), and bringing it in is how a tight, shippable
strategy turns into boil-the-ocean. This keeps faith with ADR-068's own deferral.

**What we preserve now (the seam — nearly free):** keep the consumer plane a *separate trust domain* from
the operator realm — do **not** bake "one realm, operator-only" assumptions into the workforce build.
Because identity here would be **realm-per-Product** in the same Keycloak we already run, picking it up
later is a natural extension, not a retrofit.

**The intended shape, when we do pick it up:** vend customer identity as a **paved-road capability per
Product** — a per-Product realm + OIDC endpoints provisioned from a claim (like the XEnvironment one), so
the tenant developer never operates an IdP — with `compliance_tier` driving isolation strength
(shared-realm → dedicated-realm → dedicated-DB for hipaa/pci). The fork to settle *then, not now*: does the
road stop at **authn + coarse roles** *(lean: yes — the standard road)* or also offer **fine-grained app
authz** (Cedar/OpenFGA — the one place a runtime PDP is right, ADR-053 decision 1; *lean: opt-in higher
tier*). And CIAM's genuinely-harder requirements — consent, GDPR erasure, data residency, passkeys,
abuse defense — are exactly why it's its own effort, and why per-realm isolation earns its keep.

---

## How this lands on the existing decisions

| Existing | This strategy |
|----------|---------------|
| **053/059** Keycloak IdP-of-record, access-as-code, pluggable seam, *no* central PDP | **Kept wholesale** — the spine of the operator + consumer planes. |
| **068** product-scoped model: groups=identity, roles=access, `AccessGrant`, OIDC cluster-auth, release-approver/team-admin | **Kept** — the workforce access model. **Extended** with the non-builder role catalog + the unified temporary-power model. Its CIAM deferral is **kept** — we preserve the seam, not bring CIAM into current scope. |
| **040** posture = stage×tier, break-glass | **Generalized** into eligibility-in-git + timed activation for *all* powerful roles. |
| **084** identity directory: discovered handles, PagerDuty on-call, email-never-a-key, PII-never-in-git | **Kept as the runtime resolution + handle store.** **Composed** with the new declared Person roster (access facts in git; handles in the directory; the `declared` tier bridges bootstrap-provisioning). |
| **072** GitHub org-team ownership; **039/041/047** k8s RBAC + Pod Identity | **Connectors** in the fan-out (GitHub membership; the machine plane). |

The one place to be deliberate is **084 vs. the Person roster** — keep the split clean (git = access, no
PII; directory = identity, PII) and they reinforce rather than fight.

## Hardening & operations

The model above defines *who gets what and how it's projected*. These are the security and operational
concerns *around* it — mostly absent from the prior ADRs. The first three are **must-address before
build** (core security properties, not polish); the next three are operational realities that bite within
months; the last four are named-and-deferred.

### Must-address before build

- **Authentication strength scales with role power.** Authorization says *what* you can do; authentication
  proves *it's you* — and the proof required scales with the role's power (the same grid). **Phishing-
  resistant MFA (passkeys/WebAuthn) is the default**, not SMS/email codes; **step-up auth at elevation** (a
  fresh factor when checking out temporary power — see *Power is temporary*); short, role-scoped
  session/token lifetimes; enforced in Keycloak flows (group/role-conditional, `acr` assurance) and
  **invariant across the IdP seam** (honor the upstream's assurance when federated). Harden recovery — no
  self-service reset for privileged accounts (recovery is the usual MFA backdoor). Machines: the same rule
  is short-lived workload creds, no static keys. *Defer:* device-posture / contextual conditional access.
- **Access reviews are owner re-attestation of the git-declared state.** Standing access drifts (role
  changes, ended projects, "temporary" that stuck); SOC2/ISO/HIPAA require periodic recertification.
  Because access is declared in git, a review is a **diff against one list**, not a fleet crawl, and git
  history is the audit trail. **TTLs auto-expire most grants** (ADR-068 `expiresAt`) so reviews are the
  safety net only for *standing* access; a **staleness surface** flags grants past review, near-expiry
  TTLs, never-activated eligibility, and dormant accounts (login/activation logs as evidence). Reviewer =
  the owner (team-admin for team access, access-admin for platform); cadence scales with risk. Revoke =
  delete the file. *Defer:* formal certification campaigns + separation-of-duties conflict analysis until
  an audit demands them.
- **Emergency revocation — a fast kill-switch, the inverse of break-glass.** The declarative PR path is
  deliberately slow; a compromised or rogue account needs access gone *now*. Revocation is **two acts** —
  disable future logins **and** invalidate live sessions/tokens (a disabled account keeps working on
  already-issued tokens until they expire). One trusted person can pull it (no committee mid-breach),
  loudly audited; **act-now, reconcile-after** (the proper roster PR follows). Short token lifetimes
  (above) bound the residual window.

### Operational (bites within months)

- **Identity control-plane resilience.** Keycloak (every login) and the activation controller (elevation)
  are now single points of failure. **Rule: the emergency path must not depend on the system whose outage
  is the emergency** — break-glass routes through an independent door (AWS IAM, retained per ADR-068 §6),
  never Keycloak. Make Keycloak robust (HA, backed-up CNPG DB, rebuildable from git); **fail soft** (a
  brief outage blocks *new* logins; existing sessions persist). Session lifetime is the dial between
  "limit stolen-token damage" (short) and "ride out an IdP blip" (long) — set it consciously.
- **The connectors' and robots' own identity + secrets.** Every projector, bot, and CI job needs its
  *own* credential — and the access-granting connectors are the **crown jewels** (compromise = grant
  anything). Rules: **no static keys** (short-lived, federated creds — the Pod-Identity/OIDC posture,
  extended to connectors/bots); **own identity scoped to one job** (the GitHub connector touches only
  GitHub); **owner + auto-rotation + offboarding** (robots do joiner/leaver too). Unavoidable long-lived
  tokens (e.g. PagerDuty) live in the secrets store, never git, on a rotation schedule — intersects the
  known no-rotation gap. Robots sit on the same grid, so they're access-reviewed and kill-switchable like
  anyone.
- **Drift detection & continuous reconciliation.** "Git is the source of truth" is hollow if someone can
  grant access directly in a console behind git's back — and a git-only review would never see it. A
  reconciler continuously compares live access to git: **detect-and-alert**, graduating to **auto-prune**
  (remove anything not declared — the ArgoCD model, applied to access) where safe, with a **mass-delete
  guardrail** (refuse to prune when the source looks suspiciously empty — the ADR-084 pattern). Belt-and-
  suspenders: close the side doors too (no standing console-edit rights; out-of-band change requires
  break-glass), so drift is both rare and caught.

### Named & deferred

- **Migration / no-lockout cutover.** Move from today's hand-maintained Identity Center HCL + Keycloak
  seed users to the roster by **dual-run → verify-parity → flip**, keeping the independent break-glass live
  throughout — never a big-bang.
- **Policy testing.** Treat the access model as testable: automated checks that *attempt* forbidden actions
  (a developer reaching another team, a viewer mutating) and assert they're denied, re-run on every rule
  change — proactive, above the Kyverno admission backstop (ADR-068 §9).
- **External / B2B humans** (contractors, partners, outside auditors) — scoped, clearly-marked, **TTL'd
  guest access** reusing the temporary-access machinery; not employees, not customers.
- **Compliance-framework mapping** — the model already emits the controls (least privilege, separation of
  duties via approvers, reviews, audit trail, MFA); the work is mapping them to a framework's checkboxes
  and producing evidence on demand, not new mechanism.

## Phased path (sketch)

1. **People roster + AWS generator** — add `gitops/people/`; generate Identity Center
   users/groups/assignments from it (retire the hand-maintained HCL). *Closes #647; "add a person" becomes
   one PR.* Highest value-per-effort.
2. **GitHub membership connector** — provision org-team membership from the roster (resolving handles via
   the directory). Small.
3. **Temporary-power front door** — the activation controller + timer + risk gate; wrap break-glass first.
4. **PagerDuty + Slack connectors** — rotation + channel/usergroup membership; live on-call (ADR-084 §7).
5. **OIDC-native cluster auth** — Keycloak as EKS OIDC IdP (ADR-068 §6); retire IAM-federation kubectl.

**Hardening is not a later phase.** The three must-address items (auth strength, access reviews, emergency
revocation) land *with* phase 1, not after it; resilience, robot/connector identity, and drift detection
ride the projectors as they're built.

*(Out of this roadmap: the consumer plane / CIAM — a later, separately-scoped effort once real end-users
exist.)*

## Open questions (the real forks)

1. **(Deferred) CIAM scope** — authn-only vs. authn + fine-grained authz for tenant apps — to settle *if
   and when* we build the consumer plane, not now. *(Lean: authn standard, FGA opt-in.)*
2. **Declared vs. discovered handles** — does the Person roster carry bootstrap handles (the `declared`
   tier) to enable push-provisioning before self-link, or do we wait for OAuth-link / paid SCIM and never
   put a handle in git? *(Lean: optional declared bootstrap handle, upgraded by self-link.)*
3. **Approval routing** — when a Person PR mixes a team-scoped grant and a platform-wide role, route
   approval by *what's changing* (team-lead vs. access-admin)? *(Lean: yes.)*
4. **Person record home** — one Person file per human (approval routed by content) vs. team membership in
   the Team file + platform roles central. *(Lean: one Person file.)*
5. **Standing vs. activate-only per role** — which roles are eligible-only for *our* team specifically.

## Related

- **Current state:** [identity-and-sso.md](identity-and-sso.md)
- **ADRs:** [053](../adrs/053-identity-and-cross-system-authorization-strategy.md) ·
  [059](../adrs/059-identity-topology-pluggable-idp-seam.md) ·
  [068](../adrs/068-product-scoped-and-cross-team-access-model.md) ·
  [040](../adrs/040-platform-engineer-access-model.md) ·
  [084](../adrs/084-platform-identity-directory-and-owner-resolution.md) ·
  [039](../adrs/039-per-team-developer-rbac.md) ·
  [049](../adrs/049-tenant-model-team-tenant-zone.md) ·
  [067](../adrs/067-idp-domain-model.md) · [072](../adrs/072-app-repo-naming-and-team-ownership.md)
- **Source of truth:** the git-native `Team` CRs (`gitops/teams/`, ADR-063) + the proposed
  `gitops/people/`.
