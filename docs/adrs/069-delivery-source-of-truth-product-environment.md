# ADR-069: Delivery Source-of-Truth — Product Registry + Environment Claims

**Date:** 2026-06-11

**Status:** Accepted — built + live; **refines [ADR-061](061-tenant-ingress-and-custom-domain-strategy.md).** ADR-061
established *claim-as-single-source* (the per-tenant claim is the sole registry `argocd-apps` / `policy` /
`github-oidc` derive from). [ADR-067](067-idp-domain-model.md) split `app → Product/Service` and
`Tenant → Environment`, so delivery metadata now lives across **two** objects — this ADR redesigns the
derivation and replaces "single *object*" with "single *home per fact*." Delivered **in place** via the
additive v3 cutover (2026-06-11), not via the planned rebuild; the contract is the
[platform-domain-api.md](../architecture/platform-domain-api.md) normative schema.

## Context

Today the delivery chain is **claim-as-single-source** (ADR-061): one `XTenant` claim per team carries
everything — `repo`, `environment`, `domains`, `apps.<app>` — and three consumers derive from it via
`fileset` + `yamldecode`:

- **`argocd-apps`** flattens claims to **one ArgoCD `Application` per `(team, app)`** (a Terraform resource),
  injecting the generated HTTPRoute host via a kustomize patch.
- **`policy`** (the Composition, per-namespace) reads `spec.apps`/`spec.domains`/`spec.tier` → per-tenant
  `restrict-images` (scoped `team-<team>/<app>`) + `restrict-route-hostnames`.
- **`github-oidc`** is **not** claim-derived — app repos are unwired; only a hand-maintained `var.roles` exists.

This works only because the model is **degenerate**: one product, one environment, one app per team. ADR-067
breaks every assumption:

- `repo` is now a **Product** property (stage-invariant), not a per-Environment fact.
- A Product owns **N Services**; an Environment is **`(Product × Stage[, × Customer])`** — so the unit of
  delivery is `(Environment × Service)`, not `(team, app)`.
- The same repo serves every stage → one-Application-per-`(team, app)` would create redundant Applications, and
  Terraform-resource Applications mean every promotion needs a privileged `terragrunt apply` (fighting
  self-service + promote-by-PR).

So delivery must read **two** git objects and join them, and the per-Environment fan-out must become a git
operation, not a Terraform apply. ADR-061's *spirit* (a git-native registry derivable by `fileset`) carries
forward; its *letter* ("one object") does not.

## Decision

### 1. Product is a dual-represented git registry (like Team)

A Product is authored as **`gitops/products/<team>/<product>.yaml`** (per-team dirs) and **projected as a
`Product` CR** per cluster. Delivery derives from the **git registry** via the same `fileset` mechanism it uses
today; Kyverno reads the **projected CR** at admission. No new mechanism — it mirrors Team's dual representation
exactly. Environment claims live in git too (§2) and reference the Product by key.

### 2. "One home per fact" replaces "claim-as-single-source"

Every delivery fact lives on **exactly one** object — nothing is duplicated, so drift is structurally
impossible:

| Owns *delivery-identity* (Product) | Owns *stage-realization* (Environment) |
| ---------------------------------- | -------------------------------------- |
| `repo`, image-scope (`team-<team>/<product>`) | `services` deployed + each one's **digest** |
| `domains` **owned** (the allowed vanity set) | `domains` **bound** (the subset active here, ⊆ owned) |
| `tenancy` (pooled / per-customer) | `stage`, `customer?`, `tier`, `isolation`, `quota`, `lifecycle` |

- **Join = leaf-points-up.** `Environment.spec.product` → the `(team, product)` registry entry (team derived
  via the Product). **Products never enumerate their Environments** — standing up a new stage/customer is a leaf
  addition that never touches the Product file. Delivery `fileset`s both trees and joins.
- **Layout:** `gitops/products/<team>/<product>.yaml` + `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml`.
- **Domains owns-vs-binds** (§2 of the table): a vanity host is *owned* at the Product (the brand) and *bound*
  at the Environment (only prod binds `shop.example.com`); `Environment.domains ⊆ Product.domains` is
  schema-enforced, so a dev Environment **cannot** claim the prod host.

### 3. Delivery unit: one `ApplicationSet` per Product, git-driven fan-out

Terraform provisions **one ArgoCD `ApplicationSet` per Product** (stable scaffolding). Its **git generator**
fans out over `gitops/environments/<team>/<product>/` × the Product's Services → **one `Application` per
`(Environment × Service)`**, each pointing at `Product.repo` / `Service.repoPath`.

- **Per-service granularity** matches "artifacts are per-service" (ADR-067 §7) — a single service
  promotes/rolls back independently.
- **The fan-out is a git PR, not a `terragrunt apply`.** Adding / promoting / decommissioning an Environment is
  a pure git operation ArgoCD reconciles — the precondition for self-service (ADR-062) and promote-by-PR.
- **Terraform's role shrinks** to the stable scaffolding: the per-Product ApplicationSet, the projected
  `Product` CR, and the `github-oidc` trust (§5). The **preview** ApplicationSet (already a PR generator,
  ADR-032) folds into the same per-Product family.

### 4. Promotion & digest — the mechanism is **P2's** decision; L2b injects only namespace + host

> **Revised during the L2b spike (#384).** The ApplicationSet **does not inject the digest.** ArgoCD's
> ApplicationSet template cannot natively build a *variable-length* per-service kustomize `images:` list from an
> Environment's `services` map (it needs the advanced `templatePatch`, only verifiable on a live cluster). More
> importantly, **where the digest lives and how it is promoted should not be locked in by the delivery layer.**

- **L2b (delivery):** the per-Product ApplicationSet syncs the app repo's per-stage overlay
  (`<Product.repo>/k8s/overlays/<stage>`) and injects only **namespace + hostname** — both *static per
  environment*, so no dynamic list / `templatePatch`. **Whatever digest is committed in that overlay deploys**
  (apps already commit their digest to their own overlay today, so nothing breaks meanwhile).
- **Promotion / digest home → P2 ([#377](../adrs/067-idp-domain-model.md)).** Promote-by-PR (bot-merged ≤
  staging, `release-approver`-gated prod, author ≠ approver — ADR-067 §8 / ADR-068 §7) stays the model, but the
  *digest's home* — the app-repo overlay (native, decentralised, what CI does today) **or** the platform
  Environment claim (centralised ledger, requires a propagation step into the overlay) — is decided in P2 with
  full promotion context. `Environment.spec.services.<svc>.image` stays **optional/reserved** until then.
- *(No ArgoCD Image Updater / auto-writeback — auto-writing prod would bypass the gate.)*

### 5. `github-oidc` derives one OIDC role per Product from the registry

The `github-oidc` unit `fileset`s the **Product registry** and mints **one OIDC-federated IAM role per Product**
(= per repo, one repo : one product):

- **Trusts** only that Product's `repo` (the GitHub OIDC `repository` claim) on **`main` + release tags + PR
  refs** (PR refs enable `preview: true` image builds). Dovetails with the cosign keyless identity gated by
  `githubWorkflowRepository` (ADR-050).
- **Grants** only ECR push/pull to **`team-<team>/<product>-*`** — least-privilege, product-scoped; all the
  product's Services push under that one scope.
- **Platform's own roles** (terratest, the ARC runner) stay **explicit** in `var.roles` — only *product* repos
  are registry-derived. A New-Product PR thus self-provisions its supply-chain trust.

### 6. `policy` derives product-scoped, owns/binds, per-product signature trust

- **Image scope → product-scoped.** Per-namespace `restrict-images` becomes `team-<team>/<product>-*`,
  generated by the **Composition** reading the **projected `Product` CR** (via `Environment.spec.product`). The
  Composition already owns per-team `restrict-images` post-[ADR-046](046-back-stack-for-developer-self-service.md);
  it now keys off Product.
- **Hostname allow-list → owns/binds.** Per-Environment allow-list = the generated host **+ `Environment.domains`**
  (⊆ `Product.domains`, §2).
- **Signature trust → per-product.** The platform-owned `verify-images` / `verify-attestations` (cosign/SLSA,
  which stay in the `policy` module per ADR-046) move from `verify-images-team-<team>` to a **per-product**
  identity gated by `githubWorkflowRepository = Product.repo`, derived from the **Product registry**. A product
  admits only images its own repo's CI signed.

## Consequences

- **Self-service + promotion work end-to-end.** Because the per-Environment fan-out and every promotion are git
  PRs (not Terraform applies), a developer never needs a privileged apply to ship or promote — the precondition
  ADR-062 / ADR-067 P2 assumed but the current Terraform-resource model couldn't meet.
- **Drift is structurally impossible** (§2 one-home), and the supply chain self-wires (§5) — a New-Product PR
  provisions repo + OIDC + ECR scope + ApplicationSet with nothing hand-edited.
- **Terraform shrinks; ArgoCD grows.** Delivery moves from "Terraform enumerates Applications" to "Terraform
  scaffolds, ArgoCD ApplicationSets fan out from git." More logic lives in ApplicationSet generators
  (matrix/git) — a deliberate trade for git-native delivery.
- **Migrations:** `gitops/tenant-claims/` → `gitops/products/` + `gitops/environments/`; the `argocd-apps`
  module is rewritten (per-(team,app) Applications → per-Product ApplicationSet); `github-oidc` gains registry
  derivation; the Composition's `restrict-images` keys off Product. All of this landed **in place** via the
  additive v3 cutover (2026-06-11), not via a from-scratch rebuild.
- **Open follow-on:** the generated hostname still must encode a **Service** (multi-service) and **Customer**
  (per-customer) — tracked as an ADR-060/061 extension (platform-domain-api Open-questions §3); the owns/binds
  split here closes the *ownership* half only.

## Relationships

- **Refines** [ADR-061](061-tenant-ingress-and-custom-domain-strategy.md): keeps its git-native, `fileset`-derived
  registry and the `spec.domains` → `status.domains` model; **replaces "claim-as-single-source"** with
  "one home per fact" across the Product + Environment pair.
- **Contract:** [platform-domain-api.md](../architecture/platform-domain-api.md) (the v1alpha3 schema this
  derivation reads); **implements** [ADR-067](067-idp-domain-model.md) P1 delivery (#372/#375/#376) and P2
  promotion (#377).
- **Builds on** [ADR-046](046-back-stack-for-developer-self-service.md) (Composition-owned per-tenant policies),
  [ADR-050](050-shared-build-sign-reusable-workflow.md) (shared build-sign signer identity),
  [ADR-032](032-pr-preview-environments.md) (the preview ApplicationSet it folds in), and
  [ADR-063](063-team-as-first-class-git-object.md) (the dual git-registry-+-projected-CR pattern it reuses).
- **Promotion gate** shares the `release-approver` projection with [ADR-068](068-product-scoped-and-cross-team-access-model.md) §7.
