# ADR-072: App-Repo Naming & Team Ownership

**Date:** 2026-06-16

**Status:** Accepted — **Flavor A** (drop the `app-` prefix; GitHub org Teams for ownership) is the near-term
decision. **Flavor B** (product-only repo names; registry-sourced team identity) is the documented **ideal end
state**, deferred behind two prerequisites (below).

## Context

App repos are named `app-<team>-<product>` (e.g. `app-alpha-shop`). The `app-` prefix is doing **two jobs**, only
one of which is cosmetic:

1. **Marker / guard.** `trusted-ci/build-sign.yml` refuses to build any caller that is not `app-*` — a cheap
   "is this a sanctioned app repo?" check.
2. **Unspoofable team identity (supply chain).** `build-sign` derives the team from the repo name —
   `app-<team>-<product>` → first segment after `app-` is the team (`app-alpha-shop` → `alpha`). That team scopes
   the ECR push (`team-<team>/<product>-*`) and the cosign keyless identity. It is unspoofable because **repo
   creation is platform-controlled** (the New Product template) and the prefix is required.

Two facts constrain how far we can change this:

- **The security anchor is the *repo*, not the *name string*.** The real enforcement is the per-Product **IAM
  OIDC role** (trusts that repo, scoped to `team-<team>/<product>-*` — it *denies* a push to another team's
  namespace regardless of the name), the **cosign cert** (bound to the repo via the GitHub Actions OIDC
  `repository` claim), and **Kyverno** `verify-images` (gates on `githubWorkflowRepository = spec.repo`). All of
  it is provisioned from the **Product registry** (`gitops/products/<team>/<product>.yaml`), which already carries
  `spec.team` + `spec.repo`. The team-in-the-name is a *derivation convenience*, backstopped by the IAM role.
- **GitHub Teams cannot carry the supply-chain identity.** Org-team membership is **not** in the Actions OIDC
  token, so it can never appear in a cosign cert or a Kyverno `verifyImages` rule. Org Teams are the right tool
  for **human ownership / write-access**, but the cryptographic team identity will always anchor on the repo.
- **GitHub's repo namespace is flat per org.** Two teams cannot both own `shop`. Org Teams do **not** add a
  namespace. So *product-only* repo names require either globally-unique product names or a GitHub org per team.

GitHub org Teams are **not used today** — team identity flows through Keycloak groups (Backstage RBAC, ADR-053),
the gitops `Team` CR (ADR-063), and the repo-name prefix (supply chain, ADR-050). The motivation here is (a)
nicer repo names and (b) GitHub-native team ownership of app repos.

## Decision

### Flavor A — accepted (near term)

1. **Drop the `app-` prefix.** New app repos are named **`<team>-<product>`** (e.g. `alpha-shop`). The team stays
   in the name, so it remains parseable and — crucially — keeps repo names **unique in the flat org namespace**.
2. **`build-sign` parses `<team>-<product>`** (team = first segment) instead of `app-<team>-<product>`. No change
   to the trust model — team is still recovered from a platform-controlled name and backstopped by the IAM role.
   The `app-*` guard becomes a `<team>-*` shape check (the Product registry remains the real allowlist).
3. **GitHub org Teams own the app repos.** New Team creates a GitHub org team; New Product assigns the new repo
   to it with `push` access. This is the genuinely new capability — native, auditable team write-access — layered
   *beside* (not replacing) the supply-chain identity.
4. The Product registry `spec.repo`, the per-Product OIDC role, and Kyverno all key off `spec.repo` already, so
   they follow the new name with no logic change — only the registry value changes.

Flavor A is **low-risk** (the supply-chain trust anchor is untouched in substance) and there are **zero app repos
today**, so it is a clean cutover with no migration.

### Flavor B — ideal end state (deferred)

Product-only repo names (e.g. `shop`), GitHub org Teams as the ownership layer, and the supply-chain team
**sourced from the registry / IAM role** rather than the repo name. This is conceptually cleaner (the name carries
no encoded metadata) but is gated on two prerequisites that are decisions, not just code:

- **P1 — product-name uniqueness.** Resolve the flat-namespace collision: either enforce globally-unique product
  names across teams, or adopt a GitHub org per team. Until then, `<team>-<product>` is required for uniqueness.
- **P2 — decouple `build-sign` from the name.** Source the team from the Product registry (or the GitHub Teams
  API) instead of parsing the name. This is surgery on the *unspoofable anchor of the signing chain* — it must
  stay app-team-unwritable — so it needs careful design, a new trusted-ci pin, and a full New-Product → build →
  sign → Kyverno-admit verification.

## Consequences

**Positive**
- Cleaner repo names (`alpha-shop` not `app-alpha-shop`); native GitHub team ownership/write-access.
- The supply-chain trust model is unchanged by Flavor A; the IAM role + cosign + Kyverno still anchor on the repo.
- Flavor B's path is written down with its real blockers, so it's a deliberate future step, not a vague wish.

**Negative / costs**
- The `app-` prefix's value as a visual/CI marker is replaced by the `<team>-` shape + the registry allowlist.
- Org Teams add a new surface to manage (the scaffolder App needs `Members: write`; team creation must stay
  platform-controlled or the ownership signal is spoofable).
- Two naming conventions exist transiently in docs/history until references are swept.

## Alternatives considered

- **Keep `app-<team>-<product>`** (status quo) — rejected: the prefix is redundant noise once `<team>-` already
  marks ownership.
- **GitHub org Teams as the supply-chain team identity** — rejected: org-team membership is not in the OIDC
  token, so it cannot bind the cosign cert / Kyverno gate. Org Teams are ownership, not signing identity.
- **Product-only names now (Flavor B immediately)** — deferred: blocked on P1 (namespace collision) and P2
  (build-sign decoupling); ~1 week + security-anchor risk for a name-aesthetics win.

## Related work

- **Supersedes the naming half of** [ADR-050](050-shared-build-sign-reusable-workflow.md) (`app-<team>` team
  derivation in build-sign) and the New Product naming in [ADR-062](062-self-service-tenant-provisioning.md).
- **Builds on** [ADR-067](067-idp-domain-model.md) (Team→Product→Service) and the Product registry of
  [ADR-063](063-team-as-first-class-git-object.md) as the team↔repo source of truth.
- **Complements** [ADR-053](053-identity-and-cross-system-authorization-strategy.md) (Keycloak team identity) —
  GitHub org Teams add the GitHub-native ownership layer that identity strategy did not cover.
- Tracking: the Flavor A epic + the Flavor B (P1/P2) issues.
