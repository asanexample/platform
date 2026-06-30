# People registry — `gitops/people/`

The git-native **workforce roster** (ADR-068 / identity-and-access-strategy §2.4, #886). One `Person` file per
human: who they are (a Keycloak anchor) and **what access they hold** (`grants`). This is the missing "who" — it
unifies the roster that is hand-maintained today in **two** places (the Identity Center HCL and the
`keycloak-config` seed users) into a single source of truth.

> **No live provisioning yet.** This registry + its gate are the *record*; the generators that project it into
> AWS Identity Center (#888) and Keycloak (#889) come next. Authoring is by **reviewed PR** today (the
> `people-gate`); the Backstage "manage people" templates that propose those PRs are #890.

## What's here vs. what's elsewhere

- **`gitops/people/*.yaml`** *(here)* — the humans + their role grants. **Access facts only — no PII.**
- **`gitops/teams/*.yaml`** — the teams a grant can target (the `team:` ref is validated against these).
- **`AccessGrant`** (`gitops/grants/`, ADR-068) — explicit cross-team / restricted *exceptions*, distinct from a
  Person's standing grants.
- **The runtime directory** (ADR-084, Postgres) — the identity **handles** (GitHub login, Slack id, …),
  **discovered** via one-click OAuth and tiered by trust. **Email is never a join key; PII never lives in git.**
  The roster and the directory *compose*: git says "alpha-dev is a developer on alpha"; the directory resolves
  the GitHub login; the provisioner adds it to `team-alpha`.

## Schema

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Person
metadata:
  name: sarah-chen            # kebab-case; MUST equal the filename (one Person file per human)
spec:
  person: sarah-chen          # the ANCHOR — the canonical Keycloak identity (username today; the `sub` once
                              # the Keycloak generator provisions the account, #889). No PII.
  handles:                    # OPTIONAL bootstrap handles (ADR-084 `declared` tier) — upgraded to `proven`
    github: schen             # when the human self-links via OAuth. Bridges the can't-push-before-linked gap.
  grants:                     # ≥1. Each grant is (role × reach), reach = exactly one of `team:` or `scope:`.
    - { role: developer, team: alpha }                  # standing — everyday team access
    - { role: viewer, scope: platform }                 # standing — read-only across the platform
    - { role: platform-operator, scope: platform, activation: on-demand }  # ELIGIBLE, not standing (§2.3)
```

### Fields

| Field | Required | Notes |
|-------|----------|-------|
| `metadata.name` | yes | kebab-case `[a-z][a-z0-9-]{1,30}`; must equal the filename. |
| `spec.person` | yes | The Keycloak anchor (the canonical identity). No PII; never an email. |
| `spec.handles.github` | no | Bootstrap GitHub login (`declared` tier). Other handles are discovered, not declared here. |
| `spec.grants[]` | yes (≥1) | Each: `role` + **exactly one** of `team` / `scope`, plus optional `activation`. |
| `grants[].role` | yes | A workforce role. Team grants ⊆ team-role catalog; platform grants ⊆ platform-role catalog (the catalog is formalized in #887 — until then the gate validates against a provisional set). |
| `grants[].team` | one-of | Team-scoped grant. The team **must exist** in `gitops/teams/`. |
| `grants[].scope` | one-of | Platform-scoped grant; currently only `platform`. |
| `grants[].activation` | no | `on-demand` ⇒ **eligible, not standing** (temporary-power, activated at checkout — P3). Absent ⇒ standing. |

## The gate (`people-gate`)

Every PR that touches `gitops/people/**` is validated by the **People Gate** (`.github/workflows/people-gate.yml`)
— schema shape, enum bounds, and **team/role refs exist** — and routed for approval by **content** via the
**People Approval** required check:

- A **team grant** (`team: X`) → an approval (≠ author) from **team X's `release-approver` holders** (themselves a Person grant, ADR-090) or a repo admin/maintainer (the "team lead" authority).
- A **platform grant** (`scope: platform`) or a **Person deletion** (offboarding) → an admin/maintainer approval (≠ author) — the **access-admin** authority.

Like the Teams / gitops gates, the gate runs from the **protected base** (`pull_request_target`); the PR's files
are read strictly as YAML **data**. The single-admin escape (`SOLO_MAINTAINER`) lets the sole admin self-attest.

## Locked open-question leans (#886)

- **One Person file per human** (`metadata.name` == filename). A human with many handles is still one Person.
- **Bootstrap handle is optional** — most handles are discovered (ADR-084), not declared.
