# ADR-067: IDP Domain Model — Team / Product / Service / Environment / Customer

**Date:** 2026-06-11
**Status:** Accepted (built + live, v3 model 2026-06-11) — the north-star conceptual model the golden-path work (New Service, promotion, access,
multi-cluster, customers) is built *toward*. The current platform is an explicit **degenerate instance** of it.
**Supersedes the Zone/Customer parts of [ADR-049](049-tenant-model-team-tenant-zone.md)** (keeps its
separation-of-axes insight; replaces its rigid `Zone` with a graduated isolation dial).

## Context

The self-service / golden-path effort (ADR-062 provisioning, ADR-063 Team-as-git-object, ADR-064 visibility)
modelled everything around the **Tenant** (`team-name-env`) — and because every tenant had exactly one app,
"tenant," "app," and "namespace" blurred into one thing.

Designing **repo-on-demand** broke that blur and a long design pass exposed that the model conflated several
distinct concepts, each of which bites at a different point of scale:

- An app is deployed across **many environments** (one repo, many running instances) — not 1:1 with a tenant.
- **Product** (a group of microservices in a shared namespace) is a real level the model lacked.
- **Ownership and access were the same edge** — which can't express cross-team collaboration without over-granting.
- **"Environment" meant both a *stage* and a *place*** — so HA/DR (a stage in two regions) had nowhere to live.
- **Customers** — the actual SaaS "tenant" — weren't modelled at all, and ADR-049's only nod to them (`Zone =
  dedicated account + cluster`) was far too coarse: most "give this customer their own space" just wants a
  **dedicated namespace on a shared cluster**, not a whole cluster.

This ADR fixes the **conceptual** model and its vocabulary; later ADRs implement it in phases. The terminology
is adopted **now** in every new surface; the **code rename rides the planned rebuild** (no in-place migration).

## Decision

### 1. The entity model

```text
Team ─owns─▶ Product ─owns─▶ Service                         (Service is the deployable unit)
  │             │   │           ▲
  │             │   │   Repo ─sources (1:N)─┘                 (monorepo = many services; one repo : ONE product)
  │             │   │
  │             │   └─served-to─▶ Customer                    (the consumer / SaaS "tenant"; internal or external)
  │             │
  │             └─runs-at-a-Stage-as─▶ Environment = (Product × Stage [× Customer])   ← the namespace; catalog `kind: Environment` (§10)
  │                                       ├─isolated-by─▶ Isolation (compute ladder + a separate data axis)
  │                                       └─placed-on──▶ Placement (cloud / region / account / cluster)
  │
Developer ─member-of─▶ Team                  (default access)
Developer ─granted-access─▶ Product          (EXPLICIT; enables cross-team collaboration)
Artifact (signed image digest) ─promoted-through─▶ Stages   (auto ≤ staging; gated review for prod)
Service ─depends-on─▶ Resource (DB / queue / bucket), per Environment   (shared | per-customer dedicated = data isolation)
```

| Entity | Cardinality | What it is |
|--------|-------------|------------|
| **Team** | Org 1:N Team | Owner + envelope (allowed stages/tiers/quota, max isolation). The governance + billing boundary. |
| **Product** | Team 1:N Product (N:1 owner) | A bounded context / microservice group (e.g. `shop`). Owns services; served to customers. |
| **Service** | Product 1:N Service | A deployable unit (e.g. `api`). Sourced from one repo; has a product-scoped image + runtime identity. |
| **Repo** | Repo 1:N Service | Source. Service-per-repo (default) **or** a monorepo. **Constrained to one Product.** |
| **Stage** | a shared *dimension* | A promotion rung: `dev / test / uat / staging / prod`. (Was "environment.") |
| **Environment** | Product 1:N Environment | A Product running at a Stage `(Product × Stage[, × Customer])` — a namespace, the deployable. **= catalog `kind: Environment`** (§10). (Was "Tenant.") |
| **Customer** | Product 0:N Customer | A consumer of a product (internal or external) — the tenant-in-spirit. Attaches at **prod** (+ opt-in UAT). |
| **Isolation** | per Environment | *How hard* an environment is isolated — a compute ladder + a separate data axis (§5). |
| **Placement** | Environment 1:N Placement | *Where* it physically lands: cloud / region / account / cluster (HA/DR/residency). |
| **Developer** | N:M Product (access) | Identity. Accesses products via team membership (default) **and** explicit grants. |

### 2. Vocabulary (and retiring "Tenant")

- **Customer** is the SaaS-sense tenant (the consumer). **Environment** is the `(Product × Stage[, Customer])`
  namespace. **Stage** is the dev→prod rung. **"Tenant" retires as a noun** — it was stuck on the namespace
  while the real tenant is the Customer; "multi-tenant" / "tenant isolation" survive only as *adjectives*.
- **Timing:** these terms are used in **all new surfaces now** (this ADR, the catalog System/Component/Environment,
  "New Service", new docs). The **code/CR rename** (`XTenant`, `tenant-claims/`, `restrict-tenant-envelope`, the
  gate, `spec.environment`) **rides the planned from-scratch rebuild** ([[project_planned_rebuild]]) — no
  in-place migration. Until then code keeps the legacy names; this ADR is the mapping of record.

### 3. Ownership is **not** Access (two graphs)

- **Ownership** is a *tree*: `Team → Product → Service`. Each product has exactly **one** owning team — the
  governance graph (envelope, quota, billing, accountability).
- **Access** is *many-to-many*: `Developer ↔ Product`. **Defaults** to team membership, but is **extensible
  per-product** — cross-team collaboration is an explicit Product- (or Service-) level grant, **not** dumping a
  developer into another team's group (which would over-grant everything that team owns).

The access *posture* (operate vs view, break-glass) stays derived from `stage × tier` (ADR-040); this ADR only
says **who is scoped** to a product is a different edge from **who owns** it.

> **Access-model impact (ADR-053).** Today the access model is purely **team-scoped** — `Dev-<team>` grants the
> whole of a team's footprint, and the [ADR-053](053-identity-and-cross-system-authorization-strategy.md)
> "access-model-as-code" generators + the Keycloak group/role taxonomy mirror **only** the Team. Product-scoped
> access and cross-team grants have **no representation** in that taxonomy: the only way to express "a dev on
> another team's product" is to drop them into `Dev-<other-team>`, which over-grants exactly what this section
> forbids. So **P4 below requires extending the Keycloak taxonomy and the ADR-053 generators from Team → Team +
> Product + cross-team grant**, and a distinct **release-approver** posture (separation of duties) for gated prod
> promotion (§8). That detailed identity design is **deferred to its own working session / an ADR-053 revision**,
> not specified here. **End-user / Customer authentication** (consumers signing in to a product, §6) is a
> *separate* plane from developer access — out of scope for this ADR, likely served via the ADR-052/059 upstream
> broker seam.

### 4. Stage / Environment / Placement (a stage is not a place)

- **Stage** = a logical promotion rung — what a developer reasons about and promotes to.
- **Environment** = a Product materialized at a Stage = the namespace.
- **Placement** = *where* an environment physically runs — `(cloud, region, account, cluster)`. **One environment
  → one or more placements** (`prod` in `us-east-1` + `us-west-2` for HA/DR; or `prod-eu` for residency).

### 5. Isolation is a graduated dial (replaces ADR-049's rigid Zone)

Isolation is **how hard**, decided **per-environment, defaulting from the Customer**, and it is **two orthogonal
axes**, not one cluster-or-nothing zone:

- **Compute isolation** — a ladder, cheapest → heaviest:
  `dedicated-namespace → dedicated-nodes → dedicated-cluster → dedicated-account`.
  Every environment is already its own namespace; the dial is what you add **beyond** that. The **default for a
  per-customer environment is `dedicated-namespace`** (its own namespace on the *shared* cluster — a real
  boundary, cheap); the heavier rungs are deliberate opt-ins.
- **Data isolation** — a **separate** per-resource axis: each thing a service depends on (DB / bucket / queue) is
  *shared* or *per-customer dedicated*. This rides the Service→Resource dependency model (§ phasing). It matches
  the common "shared compute, dedicated database" ask — so it is **not** a rung on the compute ladder.

Two further rules:

- **Per-environment, defaulting from the Customer:** a customer sets a sensible default; any single environment
  can dial up (prod harder than staging).
- **Compliance tier is a floor, not the whole story:** a regulated tier (`pci`/`hipaa`) forces a **minimum**
  (≥ `dedicated-cluster` + `dedicated-account`), but anyone may voluntarily dial up. Effective isolation =
  `max(tier-floor, chosen-level)` — compliance guaranteed, flexibility on top.

### 6. Customers (pooled vs per-customer)

A **Customer** is any consumer of a product — **internal or external**. A product chooses its tenancy model:

- **Pooled** — shared infra; customers are a logical/app-level concern (data partitioning, not a namespace each).
- **Per-customer** — a dedicated **Environment per customer**, at its chosen Isolation level (default
  `dedicated-namespace`).

Customers attach at **`prod`** (the live, customer-facing stage), with a **per-customer pre-prod/UAT as an
opt-in**. **`dev` / `test` / `staging` stay internal and pooled** — so the `Product × Stage × Customer` fan-out is
bounded to prod (+ optional customer-UAT), not multiplied across every stage. (Per-customer dedication is gated
by the Team envelope's `maxDedicatedIsolation` `{ cluster, account }`.)

### 7. Repo ≠ Service; identity is per-repo, artifacts are per-service

- A **Repo sources one or more Services** — service-per-repo (default golden path) **or** a monorepo — and is
  **constrained to one Product**.
- **Image identity is product-scoped:** ECR `team-<team>/<product>-<service>`, and the cosign signing identity,
  the github-oidc push-trust, and the `verify-images` match all key off that path. (So two products can each have
  an `api`.)
- **The supply-chain *identity* is per-repo; the *artifacts* are per-service.** The repo's CI is who builds and
  signs; in a monorepo it **fans out** (one image per service), and Kyverno must admit that one repo identity for
  **any** of the repo's services. This asymmetry is in the model from day one even though the starter defaults to
  service-per-repo (the monorepo "add a service to an existing repo" flow is secondary — issue #358).

### 8. Promotion (the same artifact moves up; prod is gated)

Because the image is env-agnostic, a build is **signed once and promoted by digest** dev → … → prod (never
rebuilt per stage). **Promotion to lower stages (≤ staging) auto-merges** within the envelope; **promotion to
`prod`** (and regulated stages) requires an **approving review** — separation of duties (deployer ≠ approver,
ADR-040), like the New-Team gate.

> **Implemented** (#377/#501) — the release-keyed ApplicationSet, auto ≤ staging reconciler, and gated-prod
> release-approver are live. Mechanics: [Promotion & Release](../architecture/promotion-and-release.md).

### 9. Platform-injection (manifests are placement-agnostic)

A service's manifests are **namespace- and host-agnostic**. The platform injects what varies per environment —
the namespace (`argocd-apps` `destination.namespace`), the HTTPRoute host (ADR-060), and prod-hardening
(`stage × tier`, ADR-040). So **one kustomize `base/` serves every environment**; per-stage `overlays/` exist
only for genuine app-level deltas (replicas, resources, flags). (The current `app-bravo` starter hardcodes
`namespace:` — single-env; the multi-env starter omits it.)

### 10. Catalog mapping (the whole topology is navigable)

The projection renders the model into the catalog:

```text
Group                    = Team
 (Domain, optional)      = a business area above Products (e.g. commerce ⊇ shop, checkout)
  System                 = Product            ← the services that cooperate; holds the Components
   Component             = Service            ← one per service, env-agnostic; from catalog-info.yaml
   Environment (custom kind) = Environment    ← the provisioned (Product × Stage[, × Customer]) deployment
    Resource             = per-env infra (DB / ECR / IAM / quota / policy)
```

**Why this mapping** (it is *not* the obvious `Product=Domain, Environment=System`):

- A Backstage **`System` is "components that work together to perform a function"** — that is the **Product**,
  not a deployment. So **Product = `System`** and Service `Component`s nest in it natively.
- Backstage prescribes **one `Component` per service, never one per environment** — a developer finds *one*
  service entity and sees its deployments side-by-side via plugins. So a Service `Component` carries **spanning**
  selectors (`backstage.io/kubernetes-label-selector`, `argocd/app-selector`, no namespace pin) and surfaces all
  its environments; there are **no per-`(service × env)`** entities.
- An **Environment** is a *deployment*, modeled by a relation, not membership. Backstage has no native kind for
  it (the long-running [maintainer thread #16389](https://github.com/backstage/backstage/issues/16389) converges
  on `kind: Environment` + `Component –deployedTo→ Environment`). We adopt a **custom `kind: Environment`** — our
  platform *provisions* environments as first-class, ownable, status-bearing objects, so it earns its own kind.
  It carries the **namespace-pinned** annotations + the provisioning status card (ADR-064), and `deployedTo` ties
  it to its Services.
- `Domain` is **optional** — emitted only where a real business-area grouping above Products exists, never forced.

This refines an earlier sketch (`Product=Domain, Environment=System`), which conflated the Product with its
deployments and broke `Component.spec.system`'s single-System constraint. The field-level catalog contract +
the `platform-projection` delta live in
[platform-domain-api.md](../architecture/platform-domain-api.md#open-questions--known-gaps); the rewrite is
ADR-067 **P1.3** (#373).

### 11. Current platform → target (phasing)

| Concern | Today (degenerate) | Target |
|---|---|---|
| Team | ✓ Team CR + envelope + `Dev-<team>` | — |
| Product | implicit (`name`, ≈ app) | first-class → **`System`** per `(team, product)` (§10) |
| Service / image | `spec.apps.<app>`, `team-<team>/<app>` | distinct from product; **product-scoped** `team-<team>/<product>-<service>` |
| Repo↔Service | 1:1 assumed | **1:N** (monorepo), one repo : one product |
| Environment | tenant `team-name-env` = System ✓ | ns-agnostic manifests + platform injection; rename Tenant→Environment |
| Stage vs Placement | `spec.environment`; `zone:default`, 1 cluster | split; zones → real placements (HA/DR) |
| Isolation | pooled only | graduated dial (compute ladder + data axis), tier-floored |
| Customer | unmodelled | first-class; prod(+UAT); pooled/per-customer |
| Access | team-level only | **product-level grants** (cross-team) |
| Promotion | — | promote-by-digest; **prod gated** |
| Dependencies | claim's `permissions.aws` | first-class Service→Resource graph (carries data isolation) |

**Phases** (each its own ADR/issues, built against this model):

1. **New Service** + **multi-env starter** (ns-agnostic base/overlays + injection) + **Product-as-`System`** (§10) +
   **product-scoped image identity**. (The reframed "repo-on-demand.")
2. **Promotion** (auto ≤ staging, gated prod).
3. **Customers + graduated isolation** (per-customer environments; the compute dial).
4. **Product-level access grants** (cross-team collaboration) — extends the **ADR-053** Keycloak taxonomy +
   access-model-as-code generators from Team → Team + Product + grant, and adds a release-approver posture for
   gated prod. (Its own working session / ADR-053 revision.)
5. **Placement / multi-cluster** (HA/DR) + **Service→Resource dependencies** (data isolation).

Secondary/parallel: **monorepo "add a service to an existing repo"** (issue #358).

## Consequences

- **A single coherent north star** with a consistent vocabulary; the catalog (Group/System/Component/Environment) is a
  faithful rendering, and every later feature has an obvious home.
- **The expensive separations are made cheaply, up front:** ownership/access, stage/placement, and isolation as a
  *dial* (not a binary) avoid re-plumbing RBAC, delivery, and customer isolation once cross-team work, DR, and
  dedicated customers land.
- **It honestly bounds scope** — the platform is a *subset*; we ship phases, and no phase contradicts another
  because all reference this ADR.
- **Commitments / migrations:** product-scoping the image identity renames ECR paths and the cosign/OIDC/policy
  keys; Tenant→Environment + env→Stage renames the CR/claims/policies/templates — **both ride the rebuild**, not
  in-place. The access-grant model and the Customer/isolation/promotion machinery are genuinely new (deferred,
  not designed away).
- **Terminology debt:** code keeps "tenant"/`XTenant` until the rebuild while the concept is **Environment** and
  the tenant-in-spirit is the **Customer**; we accept the lag and use the model's names in new surfaces.
- **Supersession:** retires ADR-049's `Zone` (too coarse) and its "Customer = dedicated-zone attribute only";
  keeps ADR-049's core insight that ownership and isolation are independent axes.

## Relationships

- **Normative schema:** the field-level contract for this model is
  [platform-domain-api.md](../architecture/platform-domain-api.md) (the v1alpha3 Team / Product / Service /
  Environment / Customer schemas), which supersedes the ADR-049
  [tenant-api-v2.md](../architecture/tenant-api-v2.md). Reconciling that schema is the first implementation step
  (P1's foundation — every later phase reads from it).
- **Supersedes** the Zone/Customer model of [ADR-049](049-tenant-model-team-tenant-zone.md); **refines** its
  Team/Tenant separation (promotes **Product**, splits **Stage vs Placement**, splits **Ownership vs Access**,
  replaces **Zone** with graduated **Isolation**).
- **Foundation for** [ADR-062](062-self-service-tenant-provisioning.md) (self-service),
  [ADR-063](063-team-as-first-class-git-object.md) (Team object), and
  [ADR-064](064-backstage-provisioning-visibility.md) (visibility) — the golden path implements toward this.
- **Access posture** derives from `stage × tier` per [ADR-040](040-platform-engineer-access-model.md); this ADR
  separates *who is scoped to a product* from *who owns it*.
- **Consumed by** [ADR-053](053-identity-and-cross-system-authorization-strategy.md): its access-model-as-code
  generators + Keycloak taxonomy currently mirror only the Team and must extend to **Product + cross-team grants**
  (P4 §3). End-user/Customer auth is a separate plane (the ADR-052/059 broker seam), not this ADR.
- **Delivery** (namespace/host injection, per-stage paths) builds on [ADR-061](061-tenant-ingress-and-custom-domain-strategy.md)
  (claim-as-source) and [ADR-060](060-tenant-app-hostname-convention.md) (hostname convention).
- **Monorepo** "add a service to an existing repo": issue #358.
