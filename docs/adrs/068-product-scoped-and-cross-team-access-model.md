# ADR-068: Product-Scoped & Cross-Team Access Model

**Date:** 2026-06-11

**Status:** Proposed — the concrete access model the golden path enforces. **Refines [ADR-053](053-identity-and-cross-system-authorization-strategy.md)** (the IdP + access-model-as-code *strategy*) by specifying *what the model actually is* now that [ADR-067](067-idp-domain-model.md) made **Product** a first-class level. **Rebuild-gated** for implementation (the generators + the OIDC cluster-auth cutover land with the [planned rebuild](../runbooks/platform-rebuild-from-scratch.md)); vocabulary and the data-contract are adopted now.

## Context

ADR-053 chose Keycloak as the app IdP and "access model as code" — declarative source → standard OIDC group/role claims → generated native RBAC per system. But it was written when the model was **`team == tenant`**, so the access-model-as-code generators and the Keycloak group/role taxonomy mirror **only the Team**. The intended team-scoped chain is (note: the `DeveloperAccess-<team>` IAM role + EKS access entry are **not actually provisioned today** — regression [#647](https://github.com/asanexample/platform/issues/647); only the in-cluster RoleBinding is emitted, so the AWS→kubectl hops below are the design, not the deployed state):

```text
SSO group → Dev-<team> → DeveloperAccess-<team> IAM role → EKS access entry → team-<team>:developers → namespace RoleBinding
```

[ADR-067](067-idp-domain-model.md) made **Product** a first-class level between Team and Service, and made two separations load-bearing: **ownership ≠ access** (for cross-team collaboration) and **stage ≠ placement**. The team-scoped model **cannot express** what ADR-067 requires:

- **Product-scoped access** — a developer scoped to specific products, not a team's entire footprint.
- **Cross-team collaboration** — a developer on another team's product. Today the *only* way is to add them to `Dev-<other-team>`, which **over-grants everything** that team owns — exactly the failure ADR-067's ownership/access split exists to prevent.
- **Gated prod promotion with separation of duties** — a *release-approver* posture distinct from "deployer," which the current model doesn't name.

So the access model must extend from **Team** to **Team + Product + explicit grant**. This ADR specifies that model; ADR-053's strategy (Keycloak, claims, generated native RBAC, the two enforcement planes) carries forward unchanged.

**Out of scope:** end-user / **Customer** authentication (consumers signing in to a product). That is a *separate plane* from developer access, served via the [ADR-052](052-centralized-dex-sso-broker.md)/[ADR-059](059-identity-topology-pluggable-idp-seam.md) upstream-broker seam, and is not designed here.

## Decision

Identity lives in **groups**; access lives in **roles**. Everything cross-team is an explicit, expirable, owner-approved, admission-validated grant — the opposite of "drop them in `Dev-<team>`."

### 1. Cross-team access = an `AccessGrant` object

A cross-team (or within-team-restricted) grant is a **separate `AccessGrant` CR**, authored in the **granting (owning) team's** git domain and reviewed by that team. Default **team membership grants nothing extra to write** — a member's access to the team's own products is *implicit* (see §4); only deviations from that default are objects.

```yaml
kind: AccessGrant            # lives in the OWNING team's domain
spec:
  target:                    # what is being granted
    team: alpha
    product: shop
    service: checkout        # OPTIONAL — narrows to one service (soft; see §5)
  subject: group:team-bravo  # user:<id> | group:team-<b>  (Team groups only, §2)
  posture: view              # OPTIONAL cap; default view (§3)
  expiresAt: 2026-09-01      # OPTIONAL TTL; mandatory for regulated targets (§8)
```

The grant's `target` is a `(team, product[, service])` reference — it works **before** Product is a full CR (it references by name), so the model is not chained to a later phase.

### 2. Subject — Team groups or a named user, never ad-hoc groups

`subject` is a typed ref: `user:<id>` or `group:team-<b>`. The golden path **biases to groups** (cross-team work is usually "team B's squad helps on team A's product," and a group maps cleanly onto Keycloak and stays churn-free as people join/leave). But **group subjects must be Team groups** — the *only* groups in the system are Teams (no ad-hoc/purpose-built groups). A genuine one-off collaborator uses `user:`.

This keeps a clean invariant: **every Keycloak group is a Team.** It also makes default team membership uniform — it is just the *implicit* grant `group:team-A → {all of team-A's products}`, which we simply don't write down.

### 3. Posture — a grant only ever *narrows*

A grant carries an **optional `posture` cap**, **default `view`** (least-privilege; escalate to `operate` explicitly). It composes with the existing `stage × tier` posture rule (ADR-040):

```text
effective_posture = min(grant.posture_cap, posture(stage, tier))
```

A grant can therefore only **tighten** access, never exceed what `stage × tier` already allows. Owners and grantees are asymmetric by default (an owner gets the `stage × tier` posture; a grantee is capped at `view` unless raised) — which is the point. This makes the model **safe by construction** and admission-validatable: no grant can escalate.

### 4. Default team access — all products, with a regulated/sensitive carve-out

- **Default:** a team member gets **all of the team's products** at the owner posture. Team membership = "you own everything this team owns." This matches the small-team reality and keeps the common case zero-config.
- **Escape hatch:** a product may declare **`restrictWithinTeam: true`** — then *even insiders* need an explicit `AccessGrant` (subject = an internal `user:`), reusing the exact same machinery.
- **Auto-trigger:** a **`pci` / `hipaa` tier** product is `restrictWithinTeam` **by default** — separation of duties is usually a regulatory requirement, so regulated products are least-privilege from the start.

In Keycloak terms (§5): the default is the team's product roles assigned **to the team group**; a restricted product **withholds** its role from the team group and requires explicit grants.

### 5. Keycloak taxonomy — groups = identity, roles = access

The access-model-as-code generators *synthesize* Keycloak from git, so the scheme is regular and not hand-maintained:

- **Groups = Teams.** One Keycloak group per Team (`/<team>`) holding *people*, plus `platform-admins`. That is the whole group taxonomy (§2's invariant).
- **Access = realm roles** `access:<team>/<product>:operate` and `:view`. The generator wires them:
  - *Default team access (§4):* assign the team's non-restricted product roles **to the team group** → members inherit them.
  - *Restricted/regulated (§4):* withhold the role from the team group; only explicit grants get it.
  - *Cross-team grant (§1/§2):* assign the product role **to team-B's group** (or the `user:`), at the grant's posture cap — `:view` vs `:operate` *is* the role choice.
- The emitted **groups + roles claim** carries resolved access; the per-system generators expand `access:<team>/<product>:<posture>` into k8s RoleBindings / ArgoCD policies / Backstage permissions over that product's **Environments** (namespaces).

This mirrors ADR-067's own split — **identity in groups, access in roles**.

**Service-level caveat.** A grant may target a single service (§1), but an Environment (= product × stage) is **one namespace** and k8s RBAC is namespace-scoped — so a `service`-level scope **cannot be hard-enforced below the namespace** without per-resource RBAC. Service-level is therefore **honored in Backstage/ArgoCD scoping and in the contract**, but the **k8s enforcement floor stays the namespace** (product-level). Hard per-service k8s isolation is a later/opt-in concern (it would otherwise collapse Service into Environment, contradicting ADR-067).

### 6. Cluster auth goes OIDC-native (the AWS-IAM fix)

The roles claim flows cleanly into the three already-OIDC systems (ArgoCD RBAC, Backstage permissions extending #197, and k8s RoleBindings). The snag is **how a human authenticates to the cluster**: today's `DeveloperAccess-<team>` IAM role → EKS access entry maps to a **static** k8s group, so it *structurally cannot* carry product-scope, posture, or a cross-team grant.

**Decision:** developer kubectl becomes **OIDC-native** — associate **Keycloak as the EKS OIDC identity provider**; kubectl uses an OIDC token (kubelogin), and the **Keycloak roles claim is the single source of k8s groups**. `access:<team>/<product>:<posture>` then flows straight into per-namespace RoleBindings, product-scope and cross-team grants included.

- The `DeveloperAccess-<team>` IAM federation **retires as the kubectl vehicle**.
- **IAM federation is retained only for break-glass / PlatformAdmin** ([ADR-040](040-platform-engineer-access-model.md)) — so a Keycloak outage stops *new developer* sessions but never blocks emergency access.
- Human AWS **API** access becomes a separate, narrow, rarely-needed concern (workloads already use Pod Identity, [ADR-041](041-pod-identity-for-tenant-workloads.md)) — **not** the grant carrier.

This collapses the awkward IAM-federation path into the same OIDC plane ArgoCD and Backstage already use, and is where "Keycloak is the IdP of record" always pointed.

### 7. Release-approver — gated prod, separation of duties

> **Implemented** (#501), then **revised by [ADR-090](090-governance-identity-model.md)** — the approver set is
> now **derived from `release-approver` Person grants** (the single source of truth), not the hand-authored
> `spec.roles.releaseApprover` (retired). Same gitops-gate verdict (read from base, author-excluded, fail-closed,
> ≥2 for pci/hipaa) via a required commit-status check rather than CODEOWNERS — this realizes the
> "generator-managed role, projected" intent §7 stated. Mechanics: [Promotion & Release](../architecture/promotion-and-release.md).

Promotion to prod is a GitOps operation (a **digest-bump PR**). Separation of duties is enforced by making the **access model the source** and **GitHub the enforcement**:

- `release-approver:<team>/<product>` is a **generator-managed role** (git/Keycloak = source of truth), **projected into CODEOWNERS / a required-reviewer set** on the prod path. "Cannot approve your own PR" gives separation of duties for free, reusing the New-Team/tenant-gate machinery.
- **Prod's standing posture is `view` for *everyone*, owners included** (the `stage × tier` matrix says prod is locked). Prod only ever *mutates* through the **gated promotion PR** (release-approver approves, **author ≠ approver**), with **break-glass operate** (ADR-040, audited) as the sole emergency exception. "Prod is gated" becomes literal.
- **Default holder = the team-lead**, with additional approvers designatable. For **`pci` / `hipaa`** products, **author ≠ approver is mandatory** (≥ 2 approvers required).

### 8. Lifecycle & governance — owner-gated, expirable

- **Creation/approval:** a grant is a PR adding the `AccessGrant` CR in the **owning** team's domain; the owning team's **`team-admin` approves** it (the gate). A request may be *initiated* by either side, but **approval is always the owner's**. A Backstage **"Request/Grant product access"** template drives the flow (mirrors New-Tenant).
- **Expiry & review:** an **optional `expiresAt` TTL** (recommended in the UI; **mandatory for `pci`/`hipaa`**), plus a **periodic access-review** surface flagging stale grants for the owning team to re-attest or drop. **Revocation = delete the CR** → the generator removes the role assignment on the next reconcile.
- **Governance roles:** **`team-admin`** (governs membership + grants + envelope-within-limits) is **split from** `release-approver` (gates prod deploys). **Both default to the team-lead**, separable as a team grows — so one role isn't overloaded with "who can reach my product" *and* "who can ship prod."

### 9. Enforcement — two planes, mirroring the Team envelope

Grants are powerful, so they get the same belt-and-suspenders as the tenant envelope ([ADR-062](062-self-service-tenant-provisioning.md)) — the pattern the **Team CR already uses** (projected onto each cluster so Kyverno reads it at admission, ADR-049/063):

1. **Shift-left:** an `access-grant-gate` CI workflow (mirrors `teams-gate` / `tenant-claims-gate`) validates the PR.
2. **Admission backstop:** the `AccessGrant` is **projected to the cluster**, where a Kyverno policy re-validates.

Both layers validate:

- **Ownership** — the granting team must **own the target product** (`target.team` == the grant's owning team). This also **denies transitive grants**: a grantee is not the owner, so it cannot author onward grants — only the owning team's `team-admin` can.
- **Subject** — `group:` is a **Team group** (§2); `user:` is a real identity; no ad-hoc/privileged groups.
- **No escalation / no platform target** — cannot target platform-owned products or `platform-admins`; no `cluster-admin`/wildcards; posture cannot exceed `stage × tier` (true by construction, §3, but checked).
- **Regulated rules** — `pci`/`hipaa` target → **mandatory TTL** + author ≠ approver enforced (not merely recommended).
- **Per-product grant cap** — a bound on active cross-team grants per product (an **envelope knob**, sane default, platform-overridable) — sprawl backstop.

## Consequences

- **The over-grant is eliminated.** Cross-team collaboration is an explicit, scoped, capped, expirable grant instead of dumping a developer into another team's group — the ownership/access split (ADR-067 §3) becomes real and enforced.
- **One coherent plane.** Identity = groups (Teams), access = roles, all three OIDC apps + k8s fed from the same roles claim; the awkward team-coarse IAM-federation path collapses into OIDC.
- **Rebuild-gated, honestly.** The access-model-as-code generators must extend Team → Team + Product + grant; the EKS-OIDC cluster-auth cutover changes how humans get a kubeconfig (kubelogin UX) and makes Keycloak a dependency for *new* developer sessions (mitigated by the retained IAM break-glass). Both ride the rebuild, not an in-place migration.
- **Safe by construction.** Grants only narrow (§3); ownership + no-escalation + Team-group-subject + per-product cap are admission-validated on both planes (§9). Regulated products are least-privilege and separation-of-duties by default (§4/§7/§8).
- **Bounded scope.** End-user/Customer auth is explicitly a *separate plane* (the broker seam), not solved here.
- **Service-level is soft at k8s.** Accepted: service-scope is contract + Backstage/ArgoCD intent; the k8s floor is the namespace (§5).

## Relationships

- **Refines** [ADR-053](053-identity-and-cross-system-authorization-strategy.md): keeps its IdP + access-model-as-code strategy and two enforcement planes; **extends the taxonomy + generators from Team → Team + Product + grant** and adds the `release-approver`, `team-admin` roles and the OIDC cluster-auth cutover.
- **Implements the access half of** [ADR-067](067-idp-domain-model.md) (ownership ≠ access; product-scoped; posture from `stage × tier`); this is ADR-067's **P4**.
- **Builds on** [ADR-040](040-platform-engineer-access-model.md) (posture = `stage × tier`, break-glass), [ADR-041](041-pod-identity-for-tenant-workloads.md)/[ADR-047](047-pod-identity-as-aws-identity-standard.md) (workload identity is Pod Identity — humans don't carry AWS), [ADR-063](063-team-as-first-class-git-object.md) (git-native Team + cluster projection — the pattern §9 reuses), and [ADR-062](062-self-service-tenant-provisioning.md) (the gate + deny-set machinery).
- **Identity topology** is invariant under [ADR-052](052-centralized-dex-sso-broker.md)/[ADR-059](059-identity-topology-pluggable-idp-seam.md): the upstream IdP stays pluggable; group membership feeds the Team groups; **Customer/end-user auth = the separate broker-seam plane**, out of scope here.
