# Learn: Identity & Access — orientation

Who — or *what* — is allowed to do things on this platform, and how that's controlled without turning into a
sprawl of scattered permissions nobody can audit. This is the human (and machine) side of
[The Security Model](../spine/the-security-model.md)'s "least privilege, nothing standing" — made concrete.

**Audience:** platform engineers who operate access, and anyone who's wondered "how do I get permission to
X." Developers: the **2-minute view** at the end is for you. This is a *sub-curriculum* — the biggest pieces
in one place; deeper cuts (workload identity, temporary power, the governance registry) may split out later.

**Before you start:** the [domain model](../domain-model/orientation.md) (Team / Product) and ideally
[the security model](../spine/the-security-model.md) (least privilege, zero standing trust). You should know
what an IAM role and an SSO login are, roughly.

## The question

A platform touches a *lot* of systems — AWS, Kubernetes, ArgoCD, Backstage, Grafana, GitHub, PagerDuty. Each
has its own idea of "users" and "permissions." The naive approach — manage access *in each system
separately* — is how you end up with an ex-employee still in three IAM accounts, a developer with prod admin
nobody remembers granting, and an audit that takes a week.

So: **where does "who can do what" actually live, how does it reach a dozen different systems consistently,
and how do you hand someone dangerous power without leaving it lying around?** Answer that and you understand
the platform's access model — and why nobody here holds standing admin.

## The one idea: decide once, derive everywhere, trust nothing permanently

Here's the whole model in a sentence, and it's the same declarative instinct as the rest of the platform:

> **Access is declared *once*, in git — as *who you are* and *what you're granted* — and the platform
> **derives** and **projects** it into every system automatically. Dangerous power isn't *held*; it's
> *borrowed*, briefly.**

You don't create a user in AWS, then again in Keycloak, then again in GitHub. You add a person to a git
registry with a grant, and controllers reconcile that into each system's native config. Access is a
*computed* thing — `(who you are) × (what you're granted)` — projected outward, not hand-maintained in five
consoles.

Cash out why that's worth the machinery, because it kills the failure modes from the question:

- **Offboarding** stops being a checklist you *hope* was complete — delete the Person, and access vanishes
  from every projected system on the same PR. No ex-employee lingering in three IAM accounts.
- **Audit** stops being an archaeology dig — "who can touch prod, and how did they get it?" is a `git`
  query, with the reviewing commit attached. No mystery admin nobody remembers granting.
- **Consistency** is free — the same grant means the same thing for fifty people, because it's *computed*,
  not hand-typed console by console.

None of those can happen by accident when access is a *derived function of one declared source* rather than
fifty independent piles of clicks.

> Think of it as **one HR system wired to every building's badge reader.** You don't walk to each door and
> cut a key; you update the directory once, and every lock re-keys itself — grant access and the badges
> appear everywhere, revoke it and they vanish everywhere, on the same day. **Where the metaphor breaks:**
> unlike a single badge system, each target here (AWS, Keycloak, GitHub) has its *own* internal notion of
> permissions, so the platform doesn't push one badge — it *translates* the grant into each system's native
> language. That translation step is "project," and it's the crux.

Two kinds of subject travel this model, and it's worth separating them:

- **Humans** — the *workforce* plane: platform engineers, developers, viewers, auditors. Their identity of
  record is **Keycloak**, projected to AWS (Identity Center), the apps, and (coming) GitHub/PagerDuty.
- **Workloads** — the *machine* plane: pods that need to call AWS. Their identity is **Pod Identity** —
  scoped, short-lived, no static keys.

(A third, *consumer*/CIAM plane — the end-users of products *we host* — is deliberately deferred, with its
own isolated per-Product realms. Same machinery, zero trust between planes.)

## The source of truth — a roster and a catalog, in git

Access starts as two kinds of git-native record. Here's a real person from the roster
(`gitops/people/robin-vega.yaml`):

```yaml
kind: Person
spec:
  person: robin                     # the Keycloak anchor (a named user)
  grants:
    - { role: developer, team: platform }   # standing — everyday access to the platform Team's products
```

That's the *whole* declaration: **who they are** (`robin`) and **what they're granted** (the `developer`
role, scoped to the `platform` team). Nothing about AWS ARNs or Keycloak groups — those are *derived*.

The other half is the **role catalog** (`gitops/roles/`), where each `WorkforceRole` declares its *shape*
and *how it projects*. The `developer` role:

```yaml
kind: WorkforceRole
spec:
  reach: team          # scope: their own team, nothing outside it
  power: change        # can deploy + operate (not just view)
  mode: standing       # everyday access, always active
  riskTier: standard
  identityCenter: { permissionSet: "Dev-{team}", sessionDuration: PT4H, … }   # → AWS console access
  keycloak:            { realmRole: developer, perTeamGroup: true }           # → app access
```

Read what that separation buys you: a **person** file says *nothing* about how AWS or Keycloak work; a
**role** file says *nothing* about who holds it. Onboard someone → add a Person with a grant. Change what
"developer" can do → edit one role, and it re-derives for *everyone* who holds it. Offboard → delete the
Person, and access vanishes from every projected system at once. One source, many projections.

One honest subtlety the model takes seriously: **declaring access isn't the same as *effecting* it.** The
grant in git is *intent*; the config rendered into each system is the *effect* — and a system could always
be changed out-of-band (someone clicks a console). So the mature version of "decide once" is really *decide
→ derive → project → **verify***: the platform checks that the *effected* state matches the *declared* one
and flags drift. "It's in git" is a claim to confirm, not assume — the same discipline
[the security model](../spine/the-security-model.md) applies to every control.

> **Quick check:** `robin-vega.yaml` never mentions an AWS account, ARN, or Keycloak group — yet robin gets
> AWS console access *and* app access. Where do those come from? *(They're **derived + projected**: the
> `developer` role declares how it maps into Identity Center and Keycloak; the platform computes
> `robin × developer@platform` and renders the native config in each. The grant is intent; the projection is
> the effect.)*

## The machine side — workload identity without keys

Humans aren't the only subjects. Your `shop` pod needs to read its S3 bucket — so *it* needs an identity
too, and the platform's answer is the same "no standing secret" instinct. Through **EKS Pod Identity**, a
pod assumes a scoped AWS role *via its ServiceAccount* — the real one behind `alpha`'s `shop`:

```text
Pod-alpha-shop-dev-web  →  arn:aws:iam::<workload-acct>:role/Pod-alpha-shop-dev-web
```

No access key is ever minted, stored in the image, or sat in a secret to be stolen; the pod gets
short-lived credentials at runtime, scoped to exactly what that service declared it needs (see
[the Environment API](../environment-api/orientation.md), which provisions these). Same principle as the
human side — *least privilege, nothing standing* — just for a different kind of subject. It's the "visitor
badge, not a copied master key" from [the security model](../spine/the-security-model.md), made real.

**A special machine subject worth flagging: agents.** An AI agent (like the triage copilot) gets its own
least-privilege Pod Identity like any workload — but don't mistake it for a plain one, because its
*authority* is richer. An agent often acts **on behalf of** a human or the platform, so the model keeps
*three* identities separate: (1) the agent's own workload identity, (2) its tool/model grant, and (3) the
on-behalf-of-user delegation. The governing rule is sharp: **effective authority = the *intersection* of the
agent's grant and the calling human's scope** — enforced by *trusted code at the boundary, never by the
agent itself* — and delegation only ever **attenuates** (each hop can narrow, never escalate). Crucially
it's **not a parallel model**: agents are subjects in the *same* grant model (ADR-068, extended); delegation
is just a grant. That, plus **graduated autonomy** (machine-enforced bounds on what an agent may do
*unattended*), is the [Agentic platform](../_inventory.md)'s subject — the runtime + the copilot's base
identity are live, the full delegation/autonomy machinery is largely *designed* (ADR-074/086). Flagged here
so you don't file an agent under "plain workload."

## The best part — dangerous power you *borrow*, not *hold*

Here's where the model earns its keep. Some roles are too dangerous to leave switched on: full admin,
emergency break-glass. The platform's answer is **temporary power** — you're *eligible*, but the power is
**inert until you activate it**, and it **expires**.

Look at the `break-glass` role — the emergency door:

```yaml
kind: WorkforceRole
spec:
  reach: platform
  power: manage-access
  mode: on-demand        # ← NOT standing: off by default
  riskTier: apex
  description: Full power, off by default, time-boxed and loudly audited — the independent emergency door.
  # sessionDuration PT4H — extend in 1h windows (re-tap a passkey), then re-borrow
```

The mechanism is elegant: an `on-demand` grant in the roster declares *who may borrow what* — but the
projection generators **deliberately exclude on-demand grants** from the standing config
([ADR-088](../../adrs/088-temporary-power-activation.md)). So the eligibility exists in git, but the *access
does not exist in any system* until you **activate** it — a step-up (re-prompt a passkey), a TTL, and
loud audit. When the clock runs out, it's **auto-revoked**. Nobody walks around holding apex power; they
borrow it, use it, and it evaporates.

> That's the literal **break-glass** panel — behind glass, off by default, and breaking it sets off an
> alarm. You don't carry the fire axe; it's on the wall, and grabbing it is a loud, logged, temporary act.

So the spectrum is: **standing** roles (everyday, projected and active) → **on-demand** roles (dangerous,
eligible-but-inert, activated just-in-time and auto-expired). "Nothing trusted permanently" isn't a slogan
here; it's the *default state* of your most powerful roles.

> **Quick check:** an on-demand grant is written into someone's Person file in git — so why can't they use
> that power right now? *(Because the projection generators *exclude* on-demand grants from the standing
> config — the eligibility is declared, but the access isn't rendered into any system until they *activate*
> it with a step-up + TTL. Declared ≠ active, on purpose.)*

## When it breaks — the ones you'll actually hit

- **"I'm in the roster but I can't do X."** Check whether your grant is **standing** or **on-demand** — an
  on-demand grant is *eligible but inert* until you **activate** it (step-up + TTL), and it's invisible in
  every console until you do. That's the design, not a bug.
- **"Per-team `kubectl` access isn't working."** The v3 Composition emits the in-cluster `developers`
  RoleBinding but **not yet** the `DeveloperAccess-<team>` IAM role + EKS access entry — that capability is
  *designed, not built* (#647 → #364). Use `platctl kubeconfig` / PlatformAdmin meanwhile. (It's also why
  the live-verification for *this* module reads with PlatformAdmin.)
- **"The console shows access git doesn't."** That's declared-vs-effected **drift** — the projection is
  derived *from* git, so the fix is to reconcile it (or investigate the out-of-band change), never to
  hand-edit the console into a competing source of truth.

## Recap — say it back

Try it cold: *how does access work here?* If you can say —

> "Access is **declared once in git** — a **Person** (roster) holds **grants** (role × team), a
> **WorkforceRole** (catalog) declares its reach/power/mode *and* how it **projects** — and the platform
> **derives** `(who) × (what)` and renders it into every system's native config (Identity Center, Keycloak,
> …), because each tool decides internally. **Workloads** get identity the same no-standing-keys way via
> **Pod Identity**. And **dangerous roles are borrowed, not held** — `on-demand` grants are eligible but
> *inert* until activated with a step-up + TTL, then auto-revoked. Decide once, derive everywhere, trust
> nothing permanently" —

— then you understand the platform's access model, and "who can do what, and how did they get it" is always
answerable from one place: git.

## The developer's 2-minute view

Your access is **one line in your Person file** — a grant of a role, scoped to your team. You get AWS
console + app + cluster access *derived* from it; you don't request permissions system-by-system. Need
something more powerful (prod admin, break-glass)? You don't get it standing — you **activate** it
just-in-time (a passkey step-up), use it, and it expires. To change *anyone's* access, it's a PR to
`gitops/people` — reviewed, audited, and projected everywhere on merge. No console-clicking, no lingering
permissions.

## Go deeper

- The full model + projection details: the [Reference](reference.md).
- The security framing: [The Security Model](../spine/the-security-model.md) (least privilege, zero standing
  trust); workloads in motion: [The Life of a Deployment](../spine/life-of-a-deployment.md).
- Source of truth: [Identity & Access Strategy (north star)](../../architecture/identity-and-access-strategy.md) ·
  [ADR-053 identity & authz](../../adrs/053-identity-and-cross-system-authorization-strategy.md) ·
  [ADR-059 Keycloak seam](../../adrs/059-identity-topology-pluggable-idp-seam.md) ·
  [ADR-088 temporary power](../../adrs/088-temporary-power-activation.md) ·
  [ADR-041 Pod Identity](../../adrs/041-pod-identity-for-tenant-workloads.md) ·
  [ADR-089](../../adrs/089-governance-registry-topology.md)/[ADR-090](../../adrs/090-governance-identity-model.md)
  (the governance registry).
