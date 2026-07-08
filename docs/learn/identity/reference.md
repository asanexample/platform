# Learn: Identity & Access — reference

A reference for the identity and access model, in brief. For the full walkthrough, see the
[orientation](orientation.md). Each piece here may earn its own module later.

## The shape

Decide once in git, derive `(who) × (what)`, then project it into each system's native config. Three planes,
sharing machinery, zero trust between them:

| Plane | Who | Identity of record |
| --- | --- | --- |
| **Workforce** *(built)* | platform engineers, developers, viewers, auditors | Keycloak (IdP of record) |
| **Machine** *(built)* | workloads needing AWS (agents are a richer case — below) | EKS Pod Identity (+ delegation for agents) |
| **Consumer / CIAM** *(deferred)* | end-users of hosted products | one isolated Keycloak realm per Product |

## The git source of truth

- **`Person`** (`gitops/people/`) — the roster: `spec.person` (Keycloak anchor) + `spec.grants: [{role, team}]`.
- **`WorkforceRole`** (`gitops/roles/`) — the catalog: each role declares its **shape** (`reach`,
  `power`, `mode`, `riskTier`) *and* **how it projects** (`identityCenter`, `keycloak`, …).
- **`grants`** — a grant is `role × scope`; **standing** grants are projected (active), **on-demand** grants
  are eligible-but-inert (see Temporary power).

### The role axes

- **reach** — `team` (own team) → `platform` (org-wide) → `any` (broadest).
- **power** — `look` (read) → `operate` → `change` (deploy) → `manage-access`.
- **mode** — `standing` (everyday, always active) vs `on-demand` (borrowed, expires).
- **riskTier** — `standard` … `apex` (break-glass).

Catalog today: `developer`, `team-admin`, `platform-operator`, `access-admin`, `auditor`, `viewer`,
`release-approver`, `break-glass`.

## Projection — where access lands

Each tool decides access internally, so the platform derives its native config from `(Person × Role)`
([ADR-089](../../adrs/089-governance-registry-topology.md)/[ADR-090](../../adrs/090-governance-identity-model.md)):

- **AWS** — Identity Center permission sets (console/CLI), per team.
- **Apps (ArgoCD, Backstage, Grafana)** — Keycloak realm roles / per-team groups, brokered via OIDC.
- **Cluster** — per-team RBAC (ADR-039/040).
- **Coming** — GitHub teams, PagerDuty on-call, Slack.

## Temporary power (ADR-088)

- An **`on-demand`** grant declares *eligibility* (who may borrow what) — but the projection generators
  **deliberately exclude on-demand grants** from the standing config, so the access **doesn't exist** in any
  system until activated.
- **Activate** = a step-up (re-prompt a **passkey**, the `acr.loa.map` seam) + a **TTL**; extend in windows,
  then re-borrow. **Auto-revoked** on expiry, loudly audited.
- **Built + live** (ADR-088, 2026-06-30): the eligibility model, the passkey step-up seam, *and* the
  activation **operator** (a Kubebuilder controller that mints the live grant and expires it on TTL), with a
  Backstage front door.

## Workload identity

- **EKS Pod Identity** (ADR-041/047): a pod assumes a scoped IAM role via its ServiceAccount — short-lived,
  **no static keys**. Provisioned per-Service by [the Environment Composition](../environment-api/orientation.md)
  (e.g. `Pod-<team>-<product>-<stage>-<svc>`). The platform's own add-ons moved off IRSA to Pod Identity too.
- **Agents — a richer machine subject** ([ADR-074](../../adrs/074-agentic-workloads-platform.md)): an agent
  gets its own Pod Identity plus a three-identity authority model — its own identity, its tool/model grant,
  and on-behalf-of-user delegation — where effective authority is the intersection of the agent grant and the
  human's scope, enforced by trusted boundary code (never the agent) and attenuating across chains. It's the
  same access model, with agents as grant subjects (ADR-068 extended), bounded by graduated autonomy
  ([ADR-086](../../adrs/086-autonomous-agent-access.md)). Largely designed today; the full treatment is the
  coming Agentic platform module.

## Keycloak — the pluggable seam

- Keycloak is the **IdP of record** for the workforce (ADR-053/059); it *brokers* a corporate IdP if one
  exists, so the platform never becomes the identity monopoly. Apps get **direct OIDC** to Keycloak (Dex
  retired). Admin plane hardened (passkey + sealed break-glass, ADR-087).

## Gotchas

- **Declared ≠ effected.** A grant in git is *intent*; the projected native config is the *effect*. The
  honest model verifies intent-vs-effected + drift, because a system could be changed out-of-band. Don't
  assume the console matches git without checking.
- **Per-team *cluster* (kubectl) access isn't fully provisioned.** The v3 Composition emits only the
  in-cluster `developers` RoleBinding, **not** the `DeveloperAccess-<team>` IAM role + EKS access entry
  ([#647](https://github.com/asanexample/platform/issues/647) closed superseded by OIDC-native cluster auth
  [#364](https://github.com/asanexample/platform/issues/364), still unbuilt) — use `platctl kubeconfig` /
  PlatformAdmin until built. (This is why *this shell* reads with PlatformAdmin but can't write to tenant
  namespaces.)
- **On-demand grants are invisible in every console** until activated — that's the point, not a bug.

## Glossary

- **`Person` / `WorkforceRole` / grant** — the git-native roster, role catalog, and role×scope assignment.
- **derive / project** — compute `(who) × (what)`, then render it into each target system's native config.
- **standing vs on-demand** — always-active access vs borrowed-and-expiring.
- **Pod Identity** — a pod's scoped, keyless AWS identity via its ServiceAccount.
- **IdP of record** — Keycloak; the authoritative identity source the platform projects *from*.
- **step-up** — re-authenticating (passkey) to activate higher power.

## Go deeper

- [Identity & Access Strategy (north star)](../../architecture/identity-and-access-strategy.md) ·
  [ADR-053](../../adrs/053-identity-and-cross-system-authorization-strategy.md) ·
  [ADR-059](../../adrs/059-identity-topology-pluggable-idp-seam.md) ·
  [ADR-068 access model](../../adrs/068-product-scoped-and-cross-team-access-model.md) ·
  [ADR-088 temporary power](../../adrs/088-temporary-power-activation.md) ·
  [ADR-084 owner routing](../../adrs/084-platform-identity-directory-and-owner-resolution.md).
- Substrate: [NIST Zero Trust](https://csrc.nist.gov/pubs/sp/800/207/final) ·
  [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) ·
  [Keycloak](https://www.keycloak.org/documentation).
