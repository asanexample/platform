# Workforce role catalog — `gitops/roles/`

The git-native **role catalog** (identity-and-access-strategy §2.2, #887). Each `WorkforceRole` is a real
artifact on the **reach × power** grid; a `Person` grant (`gitops/people/`) references one by name, and the
generators project it into each system: **Identity Center** (#888, AWS console access) and **Keycloak** (#889,
app access). This is the catalog P1.1 grants reference and P1.3/P1.4 generate against — it does not provision
anything by itself.

> **Distinct from the product-scoped builder roles** (#361–363, the in-cluster `developer`/`viewer` ClusterRoles
> bound per Environment). This is the **workforce** catalog: who a human *is* across the org, not the RBAC a
> Deployment binds.

## The grid

A role answers two questions — **reach** (own team · platform/org-wide) and **power** (look · operate · change ·
manage-access). Big *changes* go through reviewed PRs, not a standing god-credential, so "change everything by
hand" is deliberately empty.

| role | reach | power | mode | risk |
|------|-------|-------|------|------|
| `developer` | team | change | standing | standard |
| `team-admin` | team | manage-access | standing | elevated |
| `viewer` | any (scope-adjustable) | look | standing | standard |
| `platform-operator` | platform | operate | on-demand | elevated |
| `auditor` | platform | look | standing | elevated |
| `access-admin` | platform | manage-access | standing | **apex** |
| `break-glass` | platform | manage-access (full) | on-demand | **apex** |

Cross-team / restricted access is **not** a role — it's the explicit, expirable `AccessGrant` (ADR-068 §1).

## Schema

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: WorkforceRole
metadata: { name: developer }
spec:
  reach: team               # team | platform | any   (any = scope-adjustable, e.g. viewer)
  power: change             # look | operate | change | manage-access
  mode: standing            # standing | on-demand (borrowed/elevated power; §2.3)
  riskTier: standard        # standard | elevated | apex   (meta-governance signal, §3.6)
  description: "deploy + operate their own team's products; sees nothing outside the team"
  identityCenter:           # AWS console projection (#888 reads this). Omit for app-only roles.
    perTeam: true                                   # team reach → one permission set rendered per team
    permissionSet: "Dev-{team}"                     # {team} placeholder when perTeam
    sessionDuration: PT4H
    managedPolicies: ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    note: "inline: assume DeveloperAccess-<team> in preprod (rendered per team/account by #888)"
  keycloak:                 # app projection (#889 reads this)
    realmRole: developer
    perTeamGroup: true                              # team reach → membership flows via the <team> group
```

### Fields

| Field | Required | Notes |
|-------|----------|-------|
| `metadata.name` | yes | kebab-case; must equal the filename and the name a Person grant references. |
| `spec.reach` | yes | `team` \| `platform` \| `any`. A grant's reach must match: `team:` ⇒ reach ∈ {team, any}; `scope: platform` ⇒ reach ∈ {platform, any}. |
| `spec.power` | yes | `look` \| `operate` \| `change` \| `manage-access`. |
| `spec.mode` | yes | `standing` (everyday) \| `on-demand` (eligible, activated at checkout — §2.3 / P3). |
| `spec.riskTier` | yes | `standard` \| `elevated` \| `apex`. `apex` = the access-system itself (watch-the-watchers, §3.6). |
| `spec.identityCenter` | no | AWS Identity Center projection. Omit for app-only roles. `perTeam` ⇒ rendered once per team. |
| `spec.keycloak` | no | Keycloak projection (realm role / per-team group). |

## Meta-governance (`[must]`, §3.6)

Changing a role **re-permissions everyone who holds it at once** — the highest-blast-radius change in the system.
The `roles-gate` therefore:

- **validates** the catalog schema/enums on every PR (`validate-roles.sh` → the **Roles Gate** check);
- **reports the blast radius** of each changed role — how many `Person` grants reference it — in the sticky
  comment, and routes any catalog change to an **admin/maintainer approval** (two-person control; the
  grantor-≠-beneficiary rule) via the **Roles Approval** check (`SOLO_MAINTAINER` self-attest for the sole admin).

A grant can only reference a role that **already exists** in this catalog (read from the trusted base), so a new
role lands in its own deliberate PR *before* anyone is granted it.
