# Runbook: Manage People (joiner / mover / leaver)

> **Purpose:** add, change, or remove a person's workforce access end-to-end through the git-native
> **People registry** (`gitops/people/`). One reviewed PR per change; on apply, two generators project the
> roster into **AWS Identity Center** (console access) and **Keycloak** (app access). This is the operator
> how-to behind [identity-and-access-strategy.md](../architecture/identity-and-access-strategy.md) §2.4–2.6.
>
> **Severity:** Medium (grants/revokes access — but every change is reviewed, and most is reversible by PR)
> **On-call scope:** Infrastructure / Platform Engineering — approvals route to **team-lead** or
> **access-admin** depending on what changed
> **Source of truth:** `gitops/people/` (the roster), `gitops/roles/` (the role catalog), `gitops/teams/`
> (the teams a grant can target)
> **Generators:** `infra/live/aws/mgmt/global/identity-center/` (#888, AWS) and
> `infra/live/aws/platform/us-east-1/platform/keycloak-config/` (#889, apps)
>
> **Last reviewed:** 2026-06-28

---

## The model in one screen

A **Person** is one YAML file per human (`gitops/people/<name>.yaml`): a **Keycloak anchor** (`spec.person`,
the canonical identity — a username, **never an email, no PII**) plus a list of **grants**. Each grant is
`role × reach`, where reach is **exactly one** of `team:` or `scope:`, with an optional `activation: on-demand`:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata: { name: sarah-chen }            # kebab-case; MUST equal the filename
spec:
  person: sarah-chen                       # Keycloak anchor (the realm `sub` once provisioned). No PII.
  handles: { github: schen }               # OPTIONAL bootstrap handle (ADR-084 `declared` tier)
  grants:
    - { role: developer, team: alpha }                                     # standing — everyday team access
    - { role: viewer, scope: platform }                                    # standing — read-only org-wide
    - { role: platform-operator, scope: platform, activation: on-demand }  # ELIGIBLE, not standing
```

`grants[].role` references a role from the **catalog** (`gitops/roles/`), which carries the projections
(`identityCenter` for AWS, `keycloak` for apps) and the role's `mode` (`standing` vs `on-demand`). The roster
holds **access facts only**; the person's real identity/handles live in Keycloak + the ADR-084 directory. See
[`gitops/people/README.md`](../../gitops/people/README.md) and [`gitops/roles/README.md`](../../gitops/roles/README.md)
for the full schema.

> **Standing vs on-demand matters for what gets provisioned.** A **standing** grant becomes a live assignment
> on apply. A grant marked `activation: on-demand` (or any grant whose *role* is `on-demand`, e.g.
> `platform-operator`, `break-glass`) is **eligibility, not standing access** — it is **not** projected as a
> standing assignment in either system. Activation at checkout is ADR-088 / temporary-power (see
> [Temporary power](#temporary-power-on-demand-grants) below).

---

## Joiner — onboard a person

### 1. Open the PR (Backstage, preferred)

Backstage → **Create** → **Onboard Person**. Fill in:

- **Roster name** + **Keycloak anchor** (username, no PII), optional **GitHub handle** (bootstrap `declared`).
- **Team** + **team role** (`developer` / `team-admin` / `viewer`) — your team membership is verified
  server-side.
- Optional **platform role** (`viewer` / `auditor` / `platform-operator` / `access-admin` / `break-glass`) and
  its **activation** (`standing` / `on-demand`).

The template **proposes, never grants**: it renders `gitops/people/<name>.yaml` and opens a PR
(`person/onboard-<name>` → `main`). It does **not** auto-merge.

> **The form is the person's COMPLETE access.** Onboard renders a *fresh* file. Using an existing name
> **re-sets** that person's grants to exactly what the form selects (it is not an incremental add/remove) — so
> it doubles as a simple "mover" for a full re-grant. A true add-one-grant mutation is a manual edit (below).

**Or by hand:** create/edit `gitops/people/<name>.yaml` to the schema above and open a PR.

### 2. The gate validates + routes approval

Every PR touching `gitops/people/**` runs the **People Gate** (`.github/workflows/people-gate.yml`), which is
two required checks:

- **People Gate** (`validate-people.sh`) — schema shape, enum bounds, **team refs exist** in `gitops/teams/`,
  **role refs exist** in `gitops/roles/`, and **anchor uniqueness**. The gate runs from the protected base
  (`pull_request_target`); the PR's files are read strictly as YAML data.
- **People Approval** (`publish-verdict.sh`) — a commit status routed **by what changed** (the base↔head grant
  diff), approver ≠ author:

  | Change in the PR | Who must approve |
  |---|---|
  | A **team grant** added/removed (`team: X`) | An approver in **team X's** `releaseApprover` set, **or** a repo admin/maintainer (the "team-lead" authority) |
  | A **platform grant** added/removed (`scope: …`) | A repo **admin/maintainer** — the **access-admin** authority |
  | A **Person deletion** (offboarding) | A repo **admin/maintainer** — the **access-admin** authority |
  | A pure no-op (comment/handle edit, no grant change) | No approval required |

  Single-operator escape: `SOLO_MAINTAINER` lets an admin/maintainer **author** self-attest (separation-of-duties
  waived until a second maintainer joins). Approver sets are read only from the trusted base — a PR can't edit
  its own approval authority.

The sticky comment reports the verdict. **People PRs are deliberately not auto-merged** — they grant access and
stay human-reviewed.

### 3. What happens on merge — and on apply

Merging updates the registry. **Provisioning happens on the next apply of the two generator units**, which
derive from `gitops/people/` × `gitops/roles/` with the same `fileset`/`yamldecode` pattern:

- **AWS Identity Center** — `infra/live/aws/mgmt/global/identity-center/`. Generates Identity Store
  users/groups, permission sets, and account-assignments from **standing** grants that have an `identityCenter`
  projection. A **team** grant → a `Dev-<team>` permission set on **preprod** via a `Developers-<team>` group
  (the per-team ABAC launchpad: assume `DeveloperAccess-<team>`, deny acting on another team's tagged
  resources). A **platform** grant → the role's named permission set on its scoped accounts.
  **Apply with `-parallelism=1`** (AWS SSO races concurrent assignments on the same permission set).
- **Keycloak** — `infra/live/aws/platform/us-east-1/platform/keycloak-config/`. Generates realm users
  (`local.gen_users`) from the roster and places each in the realm group(s) their **standing** grants map to (a
  team grant → the team's group; a standing platform grant → the role's keycloak group, e.g. `access-admin` →
  `platform-admins`). App RBAC (ArgoCD / Backstage / Grafana via OIDC group claims) follows immediately. Each
  generated user gets a **temporary, must-change-on-first-login** password written to Secrets Manager at
  `platform/keycloak/seed-user/<username>`.

> **Record now, enforced on apply.** A merged roster PR is the *record*; access does not change until those two
> units are applied. Clusters are often parked and applies are manual, so **onboarding completes only when an
> operator applies `identity-center` and `keycloak-config`.** The reverse holds for offboarding (below) — plan
> for it.

---

## Mover — change a person's access

A move (new team, role change, promotion, dropping a grant) is **the same flow**: edit the person's grants and
open a gated PR. Two ways:

- **Onboard Person template** with the existing roster name — remember it **re-sets** the whole grant list to
  the form selection. Good for a wholesale re-grant; not for "add one grant, keep the rest."
- **Hand-edit** `gitops/people/<name>.yaml` for a precise add/remove of a single grant, then open a PR.

The gate routes approval **by what changed** — e.g. moving from `team: alpha` to `team: bravo` needs **both**
alpha's and bravo's lead authority (each changed team is checked); adding a platform role needs an
access-admin. Apply both generators to effect the change.

> **Ownership moves are not access moves.** Per strategy §3.2, access does not silently follow a product
> changing teams — re-granting a person is an explicit roster PR, not an automatic derivation.

---

## Leaver — offboard a person

### 1. Open the PR

Backstage → **Create** → **Offboard Person** → roster name + type it again to confirm. The
`platform:offboard-person` action opens a PR **deleting** `gitops/people/<name>.yaml`. **Or by hand:**
`git rm gitops/people/<name>.yaml` and open a PR.

### 2. Approval

A Person **deletion** routes to an **access-admin** (admin/maintainer ≠ author) on the People Approval check,
and is **never auto-merged**. (`SOLO_MAINTAINER` self-attest applies for the sole admin.)

### 3. What IS revoked on apply — and what is NOT

On the next apply of the two generators, removing the file removes the person from `var.users`, which cascades:

- **AWS Identity Center** *(applied):* the user, their group memberships, and their account-assignments are
  destroyed → **AWS console access revoked**.
- **Keycloak** *(applied):* the realm user is dropped from `gen_users` → user + group memberships removed →
  **app access** (ArgoCD/Backstage/Grafana via OIDC groups) revoked; the
  `platform/keycloak/seed-user/<username>` secret is removed.

**Be honest about the gaps — offboard does *not*, today, revoke:**

- **Anything until the generators are applied.** A merged deletion is the record; if the units aren't applied
  (parked clusters, manual applies), the person still has whatever was last projected. **An offboard isn't
  complete until `identity-center` + `keycloak-config` are applied.** For an urgent/compromise case use
  **emergency revocation** (strategy §3.6) — disabling logins + invalidating live sessions — not the routine
  roster PR.
- **Live sessions / already-issued tokens.** Existing AWS SSO sessions persist until they expire; issued OIDC
  tokens live out their TTL. Roster deletion stops *new* access, it does not forcibly kill in-flight sessions.
- **On-demand eligibility that was already activated.** A borrowed grant is cleared by its activation timer
  (ADR-088, future) / a `platctl access revoke`, not by the roster delete.
- **Connectors not yet wired to the roster.** **GitHub** org-team membership, **PagerDuty** rotations, and
  **Slack** are roadmap connectors (strategy §2.6, steps 2/4) — **not yet projected from `gitops/people/`**, so
  offboarding the roster does **not** remove them. Revoke those by hand for now.
- **Cluster `kubectl` access.** Human cluster auth is a separate plane (OIDC-native cluster auth is future,
  #364; the per-team `DeveloperAccess` cluster path is the unbuilt #647 regression). The Identity Center
  generator does **not** grant in-cluster kubectl — so it has none to revoke. Today cluster access is via
  `PlatformAdmin` / `platctl kubeconfig`.
- **User-minted secondary credentials** (PATs, AWS access keys) and the ADR-084 directory handles — outside the
  roster; rely on short lifetimes / a credential inventory.

### 4. Verify

```bash
# AWS — the Identity Store user is gone (run from the mgmt account context):
aws identitystore list-users --identity-store-id <id> \
  --query "Users[?UserName=='<name>']" --output table   # empty

# Keycloak — the realm user is gone (over the keycloak-config admin path; see keycloak-break-glass.md):
#   GET /admin/realms/<realm>/users?username=<anchor>  -> []
```

---

## Temporary power (on-demand grants)

A grant with `activation: on-demand` (or an inherently on-demand role) declares **eligibility** — who *may ever*
borrow a powerful role — kept in git and PR-reviewed. **Activation** (checking it out for a window) is separate
and, by design, **not** in git. Today the read side is built:

```bash
platctl access list  --borrowable                 # what's eligible to activate
platctl access check <person-or-anchor> <role> --scope platform   # may this principal borrow it?
```

`list` / `check` are **read-only** eligibility inspection over `gitops/people` × `gitops/roles`. `platctl
access grant`/`revoke` exist as a **controller-down break-glass fallback** (default `--dry-run`). The always-on
activation controller (timers, the Backstage front door, auto-expiry) is **future** — see ADR-088 and the
**`platctl`** skill. So: declare eligibility via the roster (this runbook); *borrowing* it is ADR-088.

---

## Related

- [identity-and-access-strategy.md](../architecture/identity-and-access-strategy.md) — the north-star model
  (§2.4 source of truth, §2.5 templates, §2.6 connector fan-out, §3.6 emergency revocation)
- [`gitops/people/README.md`](../../gitops/people/README.md) · [`gitops/roles/README.md`](../../gitops/roles/README.md)
  — the registry schemas + the gate details
- [keycloak-break-glass.md](keycloak-break-glass.md) — admin-plane recovery (e.g. to reach the Keycloak admin
  API for verification)
- [environment-deprovisioning.md](environment-deprovisioning.md) — the analogous gated-PR + reviewer pattern
  for environments
- ADRs: [068](../adrs/068-product-scoped-and-cross-team-access-model.md) (access model),
  [084](../adrs/084-platform-identity-directory-and-owner-resolution.md) (directory/handles),
  [088](../adrs/088-temporary-power-activation.md) (temporary power)
</content>
