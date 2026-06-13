# Platform Domain API — Team / Product / Service / Environment / Customer Schemas

The finalized, normative object schemas for the IDP domain model of
[ADR-067](../adrs/067-idp-domain-model.md). ADR-067 sets the *model* (Team → Product → Service; Environment =
product × stage[, × customer]; ownership ≠ access; stage ≠ placement; isolation as a graduated dial); this
document is the *contract* — the concrete field names, types, defaults, enums, and required/optional status that
the rebuild implements and that the access-model-as-code generators ([ADR-053](../adrs/053-identity-and-cross-system-authorization-strategy.md)
/ [ADR-068](../adrs/068-product-scoped-and-cross-team-access-model.md)) read from.

> **Status: normative and LIVE.** These schemas landed with the rebuild (the v3 cutover, ADR-067 Consequences)
> — not an in-place migration. They **supersede** [tenant-api-v2.md](tenant-api-v2.md) — the ADR-049 *Team /
> Tenant / Zone / Customer* contract — which retained the Team-envelope and per-app-identity design but whose
> **`Tenant` / `Zone` vocabulary and per-team scoping are replaced here** (Tenant → Environment, Zone →
> Isolation dial + Placement, app → Product/Service). This doc is the deployed contract; the live `xrd.yaml`
> (`XEnvironment`, `v1beta1`) implements it.

## Conventions

- **Vocabulary (ADR-067).** "Tenant" is **retired as a noun.** The namespace-level deployable is an
  **Environment**; the promotion rung (dev/test/staging/uat/prod) is a **Stage**; the consuming party (internal
  or external — the SaaS "tenant") is a **Customer**. "Multi-tenant" survives only as an adjective.
- **API group / version.** Kubernetes-projected objects use `platform.refplat.org/v1beta1`. The developer
  claim bumps `XTenant` (`v1alpha2`) → **`XEnvironment` (`v1beta1`)** (breaking; see
  [Migration](#migration-from-v1alpha2)).
- **Cloud-neutrality is a hard rule for author-facing fields.** A developer-authored object (Environment, and
  the author-facing parts of Product/Service/Customer) **never** names a cloud, region, account, cluster, or
  namespace. Those are *derived by placement* and written to `status`. The single deliberate exception is
  `Service.permissions`, which is **explicitly cloud-keyed** (`permissions.aws.…`) while the identity binding it
  attaches to (`serviceAccount`) stays neutral. *How* a neutral claim is realized on more than one cloud — a
  shared XRD with one Composition per cloud — is [ADR-058](../adrs/058-per-cloud-tenant-composition-strategy.md).
- **Stage is not a place** (ADR-067 §4). A **Stage** is a logical promotion rung a developer reasons about; a
  **Placement** is the concrete cloud/region/account/cluster it lands in. They are independent: one Stage can
  have several Placements (HA/DR). Author-facing fields name a Stage; Placement is derived to `status`.
- **Location, not region.** A *location* is a `(cloud, region)` pair; a *jurisdiction* (`"eu"`, `"us"`) is a
  named set of acceptable locations. Author-facing fields take a jurisdiction or an exact `cloud:region` string,
  never a bare region — this is what makes data residency and multi-cloud the same mechanism.
- **Two authorization planes, one model** (ADR-053). The **envelope plane** (`tier ∈ allowedTiers`, quota,
  allowed stages/locations, grant deny-set) is enforced at *admission* by Kyverno on the projected CRs. The
  **user-RBAC plane** (product-scoped roles, `stage × tier` posture) is propagated to each system by the ADR-053
  /ADR-068 generators. Both derive from the **Team / Product** objects below.
- **Reserved fields.** Fields marked **🔒 Reserved (deferred)** are part of the schema so the API is
  forward-compatible, but the platform does not yet *provision* them. They are modeled now because the rebuild
  **bakes the schema** — reserving an optional field is non-breaking; adding a top-level dimension later is not.
- **Ownership of authorship** (who may write each object):

  | Object | Authored by | Representation |
  | ------ | ----------- | -------------- |
  | **Team** | Platform team (a Team is granted) | Registry → Backstage `Group`; **projected as a `Team` CR** per cluster for admission |
  | **Product** | Team lead (self-service, "New Product") | Registry → Backstage `System`; **projected as a `Product` CR** for per-product policy (catalog mapping: [ADR-067 §10](../adrs/067-idp-domain-model.md)) |
  | **Service** | Developer (self-service, "New Service") | Repo-native `catalog-info.yaml` → Backstage `Component` (in the Product `System`; selectors span all envs) |
  | **Environment** | Team lead / developer (self-service) | Crossplane `XEnvironment` XR (`v1beta1`), GitOps-delivered → projected as a custom Backstage **`kind: Environment`** (ADR-067 §10) |
  | **Customer** | Platform / sales ops | Registry → Backstage entity; referenced by per-customer Environments. **No projected CR in F1** — customer *existence* validation lands with P3; F1's projected-CRD set is **four**: the `XEnvironment` XRD + the `Team` / `Product` / `AccessGrant` CRDs. The `customer`-set-iff-per-customer-prod check is structural (reads the `Product` CR). |
  | **AccessGrant** | Owning team's `team-admin` (self-service) | `AccessGrant` CR in the owning team's git domain ([ADR-068](../adrs/068-product-scoped-and-cross-team-access-model.md)) |

## Vocabulary & relationships

```text
Team ──owns──▶ Product ──owns──▶ Service ◀──sources(1:N)── Repo      (monorepo allowed; one repo : ONE product)
  │              │   └──served-to──▶ Customer                          (consumer; internal | external)
  │              └──runs-at-a-Stage-as──▶ Environment = (Product × Stage[, × Customer])   ← the namespace = Backstage custom kind:Environment (§10)
  │                                          ├── Isolation  (compute ladder + a SEPARATE data axis)
  │                                          └── Placement  (cloud / region / account / cluster — derived)
Developer ──member-of──▶ Team (default access) ; ──granted──▶ Product (explicit, cross-team — ADR-068)
Service ──depends-on──▶ Resource (DB / queue / bucket) per Environment   (shared | per-customer dedicated = data isolation)
Artifact (signed digest) ──promoted-through──▶ Stages   (auto ≤ staging; PROD gated)
```

- **Ownership is a tree** (`Team → Product → Service`); **access is many-to-many** (`Developer ↔ Product`,
  ADR-068). The schema keeps these on different edges.
- **Identity is per-repo; artifacts are per-service.** A Repo sources 1:N Services (monorepo), but one Repo maps
  to exactly **one Product**. The image identity is **product-scoped**: `team-<team>/<product>-<service>`.

## Tier profiles — a floor, not a fixed level (isolation · recovery · availability)

A `tier` references a platform-defined **profile** bundling three postures resolved from the single tier a
developer names (developers pick the level, the platform decides what it means):

| Posture | What it sets | Detail lives |
| ------- | ------------ | ------------ |
| **isolation** | minimum compute / account / cluster / network separation | the Isolation dial below |
| **recovery** | RPO, RTO, backup retention; for regulated, the minimum data-retention hold | this profile · 🔒 backup/DR deferred |
| **availability** | AZ spread + target SLO | this profile |

Default matrix (illustrative — authoritative values live with the platform-owned profile definitions):

| tier | isolation **floor** | recovery (RPO / RTO / retention) | availability |
| ---- | ------------------- | -------------------------------- | ------------ |
| `standard` | `namespace` | best-effort / next-business-day / 7d | multi-AZ, 99.5% |
| `elevated` | `nodes` (dedicated pool) | 24h / 4h / 30d | multi-AZ, 99.9% |
| `pci` / `hipaa` | `cluster` + `account` | ≤1h / ≤1h / regime-mandated (e.g. 7y) | multi-AZ, 99.95%, DR-tested |

**The tier sets a floor, not the whole story** (ADR-067 §5). A regulated tier *forces a minimum* isolation
(`≥ cluster + account`); anyone may voluntarily dial **up**. Effective isolation = `max(tier-floor, chosen)`.
Recovery and availability are derived from `tier` (never re-declared); a `Resource.backup` override may only
*strengthen* the default. An environment's availability cannot exceed what the platform region provides (the control
plane is single-region today; multi-region resilience is an out-of-schema concern).

## Object 1 — Team

The **owner**: an SSO/Keycloak group plus an **envelope** that bounds every Product it owns and every
Environment those Products realize. A Team has no namespace of itself.

- **Canonical record** — full Team definition (registry → Backstage `Group`). Source of truth.
- **Projected `Team` CR** — a minimal read-only mirror of the envelope, projected per cluster so Kyverno
  admission can read it when validating an Environment or an AccessGrant. Carries only what admission needs.

### Canonical Team record

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `name` | yes | string | — | Team key (kebab-case). Drives `Team.metadata.name`, the Keycloak **group** (`/<team>` — the only group kind, ADR-068 §2), and the `<team>-` namespace prefix. |
| `displayName` | — | string | `name` | Human label (Backstage). |
| `ssoGroup` | yes | string | — | The upstream IdP group this Team maps to (membership source, ADR-059). Root of both authorization planes. |
| `costCenter` | — | string | — | Billing / showback attribution. |
| `contacts` | — | `[]string` | `[]` | Owner emails (Backstage `spec.owner`, escalation). |
| `roles` | — | object | derived | Governance role holders: `teamAdmin` (membership + grants), `releaseApprover` (prod promotion) — **both default to the team lead**, separable (ADR-068 §7/§8). |
| `envelope` | yes | object | — | The bound on every Product/Environment the Team may author. See below. |

`envelope`:

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `allowedTiers` | yes | `[]enum` | — | Subset of `standard` / `elevated` / `pci` / `hipaa`. An Environment `tier` outside this set is **rejected at admission**. |
| `allowedStages` | yes | `[]enum` | — | Subset of `dev` / `test` / `staging` / `uat` / `prod` the Team may realize. |
| `allowedLocations` | — | `[]string` | `["*"]` | Jurisdictions/locations the Team's Environments may sit in. An Environment's `residency` must be a **subset**. `["*"]` = anywhere the platform operates. |
| `quotaCap` | yes | object | — | Per-Environment ceiling AND aggregate cap (`cpu`/`memory`/`pods`). A single Environment's quota is checked ≤ cap at admission (stateless); the **sum** across the Team's Environments is checked by the report-first rollup controller. |
| `maxDedicatedIsolation` | — | object | `{ cluster: 0, account: 0 }` | How many Environments the Team may dial to `cluster`- or `account`-level isolation (the expensive rungs). `0` = pooled namespace/nodes only. Aggregate check (report-first). |
| `maxCrossTeamGrantsPerProduct` | — | integer | `10` | Cap on active inbound `AccessGrant`s per Product (ADR-068 §9 sprawl backstop). Platform-overridable. |

### Projected `Team` CR

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Team
metadata:
  name: alpha                          # = canonical Team.name
spec:
  ssoGroup: alpha-eng                  # for RBAC generation cross-checks
  envelope:
    allowedTiers: [standard, elevated, pci]
    allowedStages: [dev, test, staging, prod]
    allowedLocations: ["eu", "us"]
    quotaCap: { cpu: "64", memory: 128Gi, pods: 400 }
    maxDedicatedIsolation: { cluster: 1, account: 1 }
    maxCrossTeamGrantsPerProduct: 10
# status: { productCount, environmentCount, aggregateQuota, dedicatedIsolationInUse }   (rollup controller)
```

## Object 2 — Product

A **deployable owned by exactly one Team** (the ownership tree's middle node). It carries the delivery identity,
the tenancy model, and the default isolation its Environments inherit. Surfaces in the catalog as a **`System`**
(the functional unit — its Service `Component`s nest in it; [ADR-067 §10](../adrs/067-idp-domain-model.md)).
Projected as a `Product` CR so per-product admission policy (image-registry scoping — the registry path is now
product-scoped, ADR-046/067) can read it.

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `name` | yes | string | — | Product key (kebab-case), unique within the Team. Drives the catalog `System`, the image path `team-<team>/<product>-…`, and the `<team>-<product>-` namespace prefix. |
| `team` | yes | string | — | Owning Team. Must reference an existing `Team`. |
| `displayName` | — | string | `name` | Human label. |
| `repo` | yes | string | — | The single `owner/repo` that sources this Product's Service(s) (one repo : one product). The claim-as-source registry for `argocd-apps` / `policy` / `github-oidc` (ADR-061). |
| `tenancy` | — | enum | `pooled` | `pooled` (customers are a logical/app-level concern) \| `per-customer` (a dedicated Environment per Customer at prod). ADR-067 §6. |
| `defaultIsolation` | — | object | tier floor | The Isolation an Environment inherits unless it dials up (see [Isolation](#isolation-the-graduated-dial)). For `per-customer` products this defaults from the **Customer** (ADR-067 §4). |
| `restrictWithinTeam` | — | boolean | `false` | If true, even team members need an explicit `AccessGrant` for this Product (ADR-068 §4). **Auto-true** when `tier` ∈ {`pci`,`hipaa`} on any Environment (separation of duties). |
| `domains` | — | `[]object` | `[]` | The vanity hostnames this Product **owns** — the allowed set (`{ host, dns }`, ADR-061), validated against team ownership at admission. An Environment **binds** a subset via `Environment.domains` (a `[]string` of `host`s); the subset check is **by `host`** (`{e.host} ⊆ {p.host}`) — so a dev Environment cannot claim the prod vanity host. The generated canonical host is implicit and never declared — today's convention is `<product>-<team>-<stage>.<baseDomain>` (per-env `baseDomain`, e.g. `shop-alpha-dev.preprod.aws.refplat.org`). **⚠️ Open (see [Open questions](#open-questions--known-gaps)):** the generated host does **not** yet encode a *Service* (multi-service products) or a *Customer* (per-customer prod) — both must be added before P1's multi-service flow / P3's per-customer model. |

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Product
metadata:
  name: shop
spec:
  team: alpha
  repo: asanexample/shop                # one repo : one product (Repo 1:N Service)
  tenancy: per-customer                  # a dedicated Environment per Customer at prod
  defaultIsolation: { compute: dedicated-namespace }
  domains:
    - { host: shop.example.com, dns: external }   # owned set; an Environment binds a subset by host
```

## Object 3 — Service

The **deployable unit** — what actually runs. A Product owns N Services; a Repo sources N Services (monorepo),
but the Repo maps to one Product. A Service is **repo-native** (declared by the repo's `catalog-info.yaml`,
surfaced as a Backstage `Component`) — it is not a heavy control-plane CR. Its delivery + identity ride the
Environment claim (below) per stage.

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `name` | yes | string | — | Service key, unique within the Product. Drives the image artifact `team-<team>/<product>-<service>`. |
| `product` | yes | string | — | Owning Product. |
| `repoPath` | — | string | `/` (repo root) | Sub-path within the Product's repo (monorepo: one path per Service). |
| `serviceAccount` | — | string | `name` | **Default** SA the Service's pods run as. A **cloud-neutral** identity is minted + bound to `(namespace, serviceAccount)` **per Environment** (AWS = a Pod Identity association). Must not carry an IRSA annotation (backstop). |
| `permissions` | — | object | `{}` | **Default cloud-keyed** grants attached to `serviceAccount`. `permissions.aws.policyStatements: []` — **deny-set-validated** at CI + admission (no `iam`/`sts`/`organizations`/`account` actions or bare `*`) AND boundary-capped at runtime (ADR-062 §4). |
| `resources` | — | map | `{}` | 🔒 **Reserved.** `<name> → ResourceSpec` — the Service→Resource dependency graph (DB / cache / objectstore / stream). Realized **per Environment**; carries the **data-isolation axis** (`shared` \| per-customer `dedicated`). See [Resource](#resource-serviceresource-dependencies). |

> **Service vs `Environment.services` (authority split).** The **`Service`** object is the *static contract* —
> repo-native (`catalog-info.yaml`), the same across every stage: identity name, default permissions, and the
> resource-dependency *declarations*. The **`Environment.spec.services.<svc>`** entry (below) is the *per-stage
> realization* — which **digest** is deployed (promotion), the `repoPath`/`preview`, and any per-stage **override**
> of `serviceAccount`/`permissions` (e.g. prod needs a tighter policy than dev). Effective value = the
> `Environment` override if present, else the `Service` default. The Service never names a digest; the Environment
> never re-declares the static contract.

## Object 4 — Environment

The **developer-authored contract** and the unit of deployment: a `(Product × Stage[, × Customer])` instance =
**one namespace** = a Backstage `System`. Replaces the ADR-049 `Tenant`. Pure **intent + constraints** — it
declares *what* it needs at a stage, never *where* it lands; Placement resolves the concrete coordinates to
`status`.

`apiVersion: platform.refplat.org/v1beta1`, `kind: XEnvironment`, **cluster-scoped**. Logical identity =
`(team, product, stage, customer?)`. Because the XR is cluster-scoped, `metadata.name` MUST be globally unique
and is therefore **team-prefixed**: `<team>-<product>-<stage>` (pooled) or `<team>-<product>-<customer>-<stage>`
(per-customer) — a bare `<product>-<stage>` collides across teams that share a product name (e.g. two teams each
with a `demo` product). Namespace = the same `<team>-<product>-<stage>` (e.g. `alpha-shop-dev`,
`alpha-shop-bigco-prod`).

### spec

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `team` | yes | string | — | Owning Team — **carried explicitly** (not derived from Product). Validated `== Product.team` at admission. *Why denormalized:* the namespace `<team>-<product>-<stage>`, the Pod-Identity role, and the Kyverno envelope policy all need `team`, and a Crossplane Composition go-template **cannot cross-CR-lookup** the Product to fetch it. |
| `product` | yes | string | — | Owning Product (the leaf-up join key → repo/owned-domains/tenancy from the Product registry). Must reference an existing `Product` (whose `team` must equal this `team`). |
| `stage` | yes | enum | — | `dev` / `test` / `staging` / `uat` / `prod`. Must be in the Team's `allowedStages`. The promotion rung — **not** a place. |
| `customer` | iff per-customer prod | string | — | The `Customer` this Environment serves. **Required iff** the Product is `per-customer` **and** `stage` ∈ {`prod`,`uat`}; forbidden otherwise (ADR-067 §6/§7 — customers attach at prod, optionally customer-UAT; dev/test/staging stay internal/pooled). |
| `tier` | — | enum | `standard` | Hardening profile (`standard`/`elevated`/`pci`/`hipaa`). Must be in `allowedTiers`. Sets the isolation **floor**. |
| `isolation` | — | object | from Product/Customer/tier | The graduated dial (compute level + data axis), defaulting from the Customer (per-customer) or Product, floored by `tier`. See [Isolation](#isolation-the-graduated-dial). |
| `residency` | — | object | `{ allowedLocations: ["*"] }` | **Hard, attested** placement constraint (jurisdiction or `cloud:region`). Must be ⊆ the Team's `allowedLocations`. Placement fails (never silently relaxes) if no placement satisfies it. |
| `quota` | — | object | tier profile default | `cpu`/`memory`/`pods` (+ optional `services`/`loadbalancers`/`pvcs`/`storage`). Validated ≤ the Team's `quotaCap`. |
| `domains` | — | `[]string` | `[]` | The vanity hosts **bound** in *this* Environment — a subset of `Product.domains` (the owned set). `Environment.domains ⊆ Product.domains` is enforced at admission (ADR-069 §2), so e.g. only the prod Environment binds `shop.example.com`. Unioned with the generated host into the Kyverno `restrict-route-hostnames` allow-list + `status.domains`. |
| `services` | — | map | `{}` | `<service> → ServiceDeploySpec`. Per-stage **realization** of each deployed Service: `{ image?, repoPath?, preview?, serviceAccount?, permissions? }`. `image` is the immutable `…@sha256:` digest promoted into this stage ([Promotion](#promotion)) — **optional**: an entry with **no `image`** is *declared but not yet deployed* (the New-Product first-deploy state). The Environment still provisions namespace/quota/identity; the per-Product ApplicationSet **skips (Environment × Service) pairs with no digest**, and the first auto digest-bump generates the workload. `serviceAccount`/`permissions` **override** the `Service` defaults (effective = override else default). Also 🔒 **reserved** ([ADR-070](../adrs/070-tenant-app-config-and-secrets.md)): `config` (per-stage non-secret env → a ConfigMap, in git) and `secrets` (the bound secret keys; **values never in git** — written via the portal/platctl to Secrets Manager, synced by an ESO `ExternalSecret`). |
| `lifecycle` | — | object | `{ phase: active }` | `phase: active \| suspended \| decommissioning`. Reversible suspend zeroes the ResourceQuota (ADR-062 #283); hard-delete is gated decommission-first + reviewed; ECR retained (`Orphan`). |

### status (derived — never authored)

| Field | Type | Purpose |
| ----- | ---- | ------- |
| `placement.cloud` / `.region` / `.account` / `.cluster` / `.namespace` | string | The concrete coordinates the placement engine resolved (ADR-067 §4 — split from Stage; a Stage may map to multiple placements for HA/DR). |
| `isolationRealized` | object | The effective `max(tier-floor, chosen)` compute level + data-axis realization. |
| `domains[]` | object | Per-host `{ host, state }` (Active / Pending), unioned from the generated host + Product `domains` (ADR-061). |
| `lifecycle.phase` / `.retentionUntil` / `.exitAttestation` | string | Phase + (regulated) retention hold + certified-exit evidence reference. |
| `conditions[]` | — | Standard XR conditions + `ResidencyAttested` (the placement — and any `resources` — provably satisfy `residency`). |

### Canonical Environment claim

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: XEnvironment
metadata:
  name: shop-bigbank-prod                       # logical identity = (product, stage, customer?)
spec:
  product: shop                                 # → Product → Team (envelope, identity, default isolation)
  stage: prod                                   # dev | test | staging | uat | prod  (a rung, not a place)
  customer: bigbank                             # required: per-customer product at prod
  tier: pci                                      # hardening floor (∈ Team.allowedTiers)
  isolation: { compute: dedicated-cluster }     # dialed up from the namespace floor; data axis below
  residency: { allowedLocations: ["eu"] }       # HARD constraint, ⊆ Team.allowedLocations
  quota: { cpu: "8", memory: 16Gi, pods: 40 }   # validated ≤ Team.envelope.quotaCap
  services:
    api:
      repoPath: services/api
      serviceAccount: shop-api                  # → a cloud-neutral identity is minted + bound
      permissions:
        aws:
          policyStatements:
            - sid: ReadCustomerBucket
              effect: Allow
              actions: ["s3:GetObject"]
              resources: ["arn:aws:s3:::asanexample-team-alpha-*/*"]
      resources:                                 # 🔒 reserved — per-customer dedicated DB (data isolation)
        db: { kind: relational, engine: postgres, isolation: dedicated }
  lifecycle: { phase: active }
# status.placement: { cloud, region, account, cluster, namespace }     (derived)
# status.isolationRealized, status.domains[], ResidencyAttested condition
```

## Isolation (the graduated dial)

Isolation is **two independent axes** (ADR-067 §5/§6), set **per-Environment, defaulting from the Customer**
(per-customer) or the Product, and **floored by `tier`** (`effective = max(tier-floor, chosen)`). It replaces
ADR-049's rigid `Zone`.

**Axis 1 — compute** (a ladder; each rung strictly stronger):

| `isolation.compute` | Boundary | Realized by Placement |
| ------------------- | -------- | --------------------- |
| `shared-namespace` | namespace (PSA + Kyverno + NetworkPolicies) | shared stage cluster, shared account |
| `dedicated-namespace` *(default per-customer)* | own namespace, dedicated quota | shared stage cluster |
| `dedicated-nodes` | + dedicated node pool (taints/tolerations) | shared cluster, dedicated subnet/egress |
| `dedicated-cluster` | own cluster | dedicated cluster (regulated floor) |
| `dedicated-account` | own cloud account + cluster | dedicated account (strongest; counts against `maxDedicatedIsolation`) |

**Axis 2 — data** (separate, per-Resource — "shared compute, dedicated DB"): each `Service.resources.<r>` is
`shared` or per-customer `dedicated`, **independent** of the compute rung. Lives on the Service→Resource graph,
not the compute ladder. See [Resource](#resource-serviceresource-dependencies).

> The compute boundary is the unit of **hard** isolation; the Environment is the unit of **soft** isolation
> within it. Regulated Environments default to *sharing* a per-`(stage, regime)` compliance-boundary cluster
> (namespace-isolated within), escalating to `dedicated-cluster`/`-account` only as an explicit exception — not
> one cluster per Environment.

## Placement (derived — split from Stage)

**Placement** is the concrete `(cloud, region, account, cluster, namespace)` an Environment runs in. It is
**not** authored — the placement engine resolves it from the Environment's `stage`, `residency`, `isolation`,
and `tier`, and writes it to `status.placement`. Because Stage ≠ Placement, **one Stage can resolve to multiple
Placements** (HA/DR, multi-region) without changing the claim. The federated model (ADR-048) maps directly: a
Placement *is* a cluster running its own Crossplane + Composition; the claim is routed to that control plane.

🔒 Multi-cluster / multi-region placement is **reserved** — today every Environment resolves to the single
workload cluster (a degenerate placement). The schema carries the full coordinate set so HA/DR is a non-breaking
activation (ADR-067 P5).

## Resource (Service→Resource dependencies)

🔒 **Reserved** (the data paved-road, ADR-067 P5). `Service.resources.<name>` declares a cloud-neutral stateful
dependency, realized **per Environment**, carrying the **data-isolation axis**.

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `kind` | yes | enum | — | `relational` / `cache` / `objectstore` / `stream` — the cloud-neutral category, never a product. |
| `engine` | — | string | — | Interface hint (`postgres`/`redis`/`kafka`) — the contract the app codes against, not the implementation. |
| `class` | — | string | tier default | Platform-defined size/durability class (a reference, like `tier`). |
| `isolation` | — | enum | from Environment | `shared` \| `dedicated` (per-customer) — the **data axis**, independent of the compute rung. |
| `serviceAccount` | — | string | — | The Service SA granted access — binds to per-Service identity. |
| `backup` | — | object | tier recovery default | Override that may only **strengthen** the tier's recovery posture. |

Realized data **inherits the Environment's `residency`** (placement validates data location ⊆ `allowedLocations`,
closing the compute-residency-without-data-residency gap) and the tier's recovery posture.

## AccessGrant (cross-team & within-team-restricted access)

Cross-team access is a separate **`AccessGrant`** object, specified in full by
[ADR-068](../adrs/068-product-scoped-and-cross-team-access-model.md) (§1). Summarized here because it is part of
the projected-CR + admission surface:

```yaml
kind: AccessGrant                 # lives in the OWNING team's git domain; projected for admission
spec:
  target:  { team: alpha, product: shop, service: api }   # service OPTIONAL (soft at k8s; §5)
  subject: group:team-bravo                                # user:<id> | group:team-<b>  (Team groups only)
  posture: view                                            # OPTIONAL cap; default view; min(cap, stage×tier)
  expiresAt: 2026-09-01                                    # OPTIONAL TTL; mandatory for regulated targets
```

Default **team membership grants nothing to write** — a member's access to the team's own Products is implicit.
Only cross-team or `restrictWithinTeam` deviations are objects. Enforcement (ownership, Team-group subject,
no-escalation, regulated rules, transitive-deny, per-product cap) is the two-plane model of ADR-068 §9.

## Customer

A **first-class consumer** of a Product (ADR-067 §6) — **internal or external** (the SaaS "environment" in spirit).
It is the *default source* of a per-customer Environment's Isolation, and carries the compliance/residency/exit
contract. Referenced by `Environment.spec.customer`.

| Field | Required | Type | Purpose |
| ----- | -------- | ---- | ------- |
| `name` | yes | string | Customer key, referenced by `Environment.spec.customer`. |
| `displayName` | — | string | Human label. |
| `kind` | — | enum | `internal` / `external` — informational; isolation is a per-product decision, not forced by kind. |
| `defaultIsolation` | — | object | The Isolation per-customer Environments inherit unless dialed up (default `{ compute: dedicated-namespace }`). |
| `complianceNeeds` | — | `[]enum` | Regimes the customer contractually requires (`pci`/`hipaa`/…) — raises the tier floor for their Environments. |
| `residency` | — | `[]string` | Contractual jurisdiction(s) — constrains placement location for their Environments. |
| `encryption` | — | object | 🔒 **Reserved.** `keyCustody` (`platform-managed`/`customer-managed`/`customer-hosted`) + optional `keyRef` — the BYOK/HYOK contract. |
| `exit` | — | object | 🔒 **Reserved.** `retention` (contractual hold) + `dataDestruction` (`certified`/`standard`) — parameterizes `decommissioning` across all the customer's Environments + dedicated-resource teardown + key destruction. |
| `contacts` | — | `[]string` | Account/escalation contacts. |

```yaml
name: bigbank
displayName: BigBank PLC
kind: external
defaultIsolation: { compute: dedicated-cluster }
complianceNeeds: [pci]
residency: ["eu"]
encryption: { keyCustody: customer-managed }     # 🔒 BYOK — dedicated CMK
exit: { retention: 7y, dataDestruction: certified }
contacts: ["platform-account-team@example.com"]
```

## Reserved dimensions (modeled now, realized post-rebuild)

| Dimension | Reserved as | Realized when | Why it must be in the model now |
| --------- | ----------- | ------------- | ------------------------------- |
| **Resources / data services** | `Service.resources` + `Resource.isolation` | Data paved-road (ADR-067 P5) | Without it, `residency` attests *compute* placement but not *data* placement; and the data-isolation axis ("dedicated DB") has nowhere to live. |
| **Placement / multi-cluster** | `Environment.status.placement` (full coordinate set) | Placement engine (ADR-067 P5) | Stage≠Placement (HA/DR) requires the coordinates to exist as a derived set from day one; adding them later reshapes status. |
| **Recovery / availability** | `tier` profile (derived) + `Resource.backup` | Backup/DR system (ADR pending) | A `pci` tier *implies* RPO/RTO/retention; if the tier doesn't carry it, recovery posture has no home. |
| **Key custody (BYOK/HYOK)** | `Customer.encryption` (+ Environment override) | KMS/CMK paved-road | Customer-managed keys gate dedicated/regulated customers; bolting a key axis on later reshapes Customer. |
| **Lifecycle / exit** | `Environment.lifecycle`, `Customer.exit` | Decommission workflow + evidence | Contractual customer isolation implies a contractual *exit* (certified destruction, retention holds, key destruction). |
| **Consumption guarantees (QoS)** | *Not reserved — named omission* | Deferred | `quota` / `quotaCap` is a **cap, not a reservation**. Priority / guaranteed-capacity tiers consciously deferred. |

## Identity from the model (ADR-053 / ADR-068 generators)

The access-model-as-code compiles **one** source — these objects — into each system's native config. **Identity
lives in groups (= Teams); access lives in roles (= products at a posture)** (ADR-068 §5).

| Generated artifact | Read from | Result |
| ------------------ | --------- | ------ |
| Keycloak **group** (= Team) | `Team.name`, `Team.ssoGroup` | One group per Team; people only. Every Keycloak group is a Team. |
| Keycloak **role** `access:<team>/<product>:{operate\|view}` | `Product`, `AccessGrant` | Assigned to the team group (default), withheld for `restrictWithinTeam`, or assigned to a grant subject (cross-team) at its posture cap. |
| Keycloak role `release-approver:<team>/<product>` | `Team.roles.releaseApprover`, `Product` | Projected into CODEOWNERS / required-reviewers on the prod path (ADR-068 §7). |
| Kubernetes RoleBinding (per Environment namespace) | the resolved roles claim, `Environment.status.placement.namespace` | `access:<team>/<product>:<posture>` → operate/view ClusterRole bound in the namespace. **Developer cluster auth is OIDC-native** (Keycloak = EKS OIDC IdP; ADR-068 §6) — the roles claim is the single source of k8s groups. |
| ArgoCD policy | `Product`, the roles claim | Product-scoped sync/logs (operate) or read (view) on the Product's apps. |
| Backstage permission policy (#197) | the roles claim, ownership refs | Product-scoped operate/view (honors service-level scoping, §5). |
| Image-registry / signing scope | `Product.name`, `Service.name`, `Team.name` | ECR path + cosign `verify-images` keyed on `team-<team>/<product>-<service>` (ADR-067 §7). |

### Developer access (posture)

The **posture** is derived from `stage × tier` under ADR-040 (kubectl is operate/debug, never authoring); an
`AccessGrant` may only *narrow* it (default `view`, ADR-068 §3):

| Stage × tier | Scope | Standing level | Elevation |
| ------------ | ----- | -------------- | --------- |
| dev / test / staging (any) | product-scoped | operate | — |
| prod / standard | product-scoped | **view** (prod is gated for all) | mutate only via gated promotion (author ≠ approver); break-glass operate (time-boxed, audited) |
| prod / regulated | product-scoped + `restrictWithinTeam` | **view** | gated promotion + break-glass; deployer ≠ approver, ≥2 approvers |

## Promotion

The same **signed artifact (by digest)** moves up the Stage ladder (ADR-067 §8): **auto-promote ≤ staging**,
**gated review for prod** (separation of duties — the `release-approver` gate above). Promotion is a digest-bump
to the next stage's `Environment.spec.services.<svc>` source, not a rebuild — the identical image promotes.
Detailed mechanism is ADR-067 P2 (#377), sharing the `release-approver` projection with ADR-068 P4.5 (#366).

## Envelope enforcement (the admission plane)

Kyverno on the projected CRs is the **envelope plane** — the bypass-proof guardrail (it fires however the claim
arrived), reading the projected `Team` / `Product` CRs:

- **Stateless, hard-enforced at admission (Environment):** `tier ∈ Team.allowedTiers`,
  `stage ∈ Team.allowedStages`, `residency ⊆ Team.allowedLocations`, `quota ≤ quotaCap`, `customer` set iff
  per-customer prod, `isolation ≥ tier-floor`, image registry ⊆ `team-<team>/<product>` scope.
- **Stateless, hard-enforced at admission (AccessGrant):** ownership (granting team owns `target`),
  Team-group subject, no platform target / no escalation, regulated TTL + author≠approver (ADR-068 §9).
- **Stateful / aggregate, report-first:** sum of Environment quotas ≤ cap, dedicated-isolation in use ≤
  `maxDedicatedIsolation`, active grants per product ≤ `maxCrossTeamGrantsPerProduct`. A rollup controller
  writes `Team.status` and alerts; hard-enforce only if a Team actually pushes a cap.

## Open questions & known gaps

This schema is internally consistent but **not yet complete** — splitting `app → Product/Service` and
`Tenant → Environment` opens structural questions the v1alpha2 model never had to answer. Each below needs a
decision (most a small design pass / ADR) **before its phase ships**; the two marked ⛔ are **foundational** and
should be resolved before P1 implementation starts.

1. **✅ Delivery source-of-truth split — RESOLVED by [ADR-069](../adrs/069-delivery-source-of-truth-product-environment.md).**
   Delivery now reads **two** git objects joined leaf-up (Product registry for repo/owned-domains/image-scope;
   Environment for stage/services/digest/bound-domains/quota) under "one home per fact"; `argocd-apps` becomes
   **one ApplicationSet per Product** generating one Application per `(Environment × Service)` from git (no
   per-change apply); `github-oidc` derives one OIDC role per Product; the Composition keys `restrict-images` off
   the projected `Product` CR. This is the foundation P1.2/P1.5/P1.6 + P2 build on.

2. **✅ Catalog cardinality — RESOLVED in [ADR-067 §10](../adrs/067-idp-domain-model.md) (post-research).**
   Backstage prescribes **one `Component` per service** (plugins span environments via label-selectors), and a
   `System` is the functional unit — so **Product = `System`** (Components nest natively), **Service = `Component`**
   (spanning selectors), and **Environment = a custom `kind: Environment`** related by `deployedTo` (per the
   maintainer direction in backstage#16389), carrying the namespace-pinned annotations + the #285 status card.
   The projection rewrite (emit `System`/`Component`/`Environment`, re-point #285/#284 from `kind=system`) is
   P1.3 (#373).

3. **Hostname under multi-service + per-customer** *(partly addressed: ADR-069 §2 added the domains owns/binds
   split, closing the ownership half).* The generated host `<product>-<team>-<stage>` encodes the stage (good)
   but **not a Service** (a multi-service product needs per-service routing) or a **Customer** (per-customer
   prod). ADR-060/061 still need a generated-host extension — e.g. `<service>-<product>-<team>-<stage>` and a
   customer component/subdomain — before P1's multi-service flow and P3's per-customer model.

4. **✅ New Product lifecycle — RESOLVED.** There is an **explicit `New Product`** scaffolder template (the
   primary repo-on-demand flow), separate from `New Service`:
   - **New Product** (within-envelope **team-self-service**, automerge gate — like New-Environment): pick team +
     product + **language (Go / Node / Python)** + first-service name → creates the repo **`<team>-<product>`**
     on-demand, seeded from the chosen **language skeleton + the shared platform overlay**; opens the
     platform-repo PR adding `gitops/products/<team>/<product>.yaml` + the `dev` `XEnvironment` claim (image
     initially empty). The first CI build fills the digest via an auto-merged bump → first deploy = first
     promotion to `dev`.
   - **New Service** = add a Service to an **existing** Product's repo (the monorepo flow, **#358**).
   - **Golden-path starters** live in a dedicated **`asanexample/golden-path-starters`** repo: `/go`, `/node`,
     `/python` skeletons (app source + Dockerfile + the runtime contract: `/healthz`, `/readyz`, `PORT`,
     graceful shutdown, non-root, `ClusterIP`, named SA) **+ a `/_platform` shared overlay** (`k8s/base` +
     overlays, the `trusted-ci/build-sign.yml` thin-caller CI, `catalog-info.yaml`). The platform contract is
     authored **once** in `_platform` and composed onto every language — adding a language is a new skeleton, not
     a flow change. The CI is language-agnostic (build-sign is Dockerfile-based). **Prereq:** create the starters
     repo + grant the scaffolder App read access.

5. **Customer onboarding fan-out.** Onboarding a Customer to a `per-customer` Product must provision a
   per-customer Environment (prod, opt-in UAT) — and across *every* such Product the customer consumes. There is
   no described mechanism for that fan-out (N customers × M products). *A P3 provisioning concern; flag now so the
   Customer object carries what the fan-out needs.*

6. **Promotion artifact tracking.** Promote-by-digest needs a home for "which digest is in which stage" and the
   bump proposal/record. `Environment.spec.services.<svc>` holds the *current* digest, but the cross-stage
   ledger + the gated-bump workflow are unspecified (P2 / #377).

7. **Cost & showback granularity.** `costCenter` is **Team-level only.** The Product (a `Domain`) is the natural
   product-line cost unit, and per-customer Environments need per-customer **chargeback**. The cost model needs a
   Product + Customer attribution axis (ties to the upcoming cost-management effort).

8. **East-west / service identity.** The `Service` object names a workload identity for *AWS* access (Pod
   Identity) but is not connected to **service-to-service** identity ([ADR-057](../adrs/057-service-identity-and-east-west-zero-trust.md)
   — SPIFFE/mTLS). How Services in an Environment authenticate to each other and to their `Resource`s is unmodeled.

9. **✅ Preview / ephemeral environments — RESOLVED: runtime-only, not a gitops Environment.** PR previews
   ([ADR-032](../adrs/032-pr-preview-environments.md)) stay **delivery-layer ephemerals** — generated by the
   per-Product ApplicationSet's **PR generator** into the `dev` Environment's namespace with the `-pr-*` host (as
   today), torn down on PR close. They are **not** `XEnvironment` claims, so `stage` stays `dev…prod` (no
   `preview` value) and there is no per-preview envelope/gitops object. (L2b owns the PR generator.)

10. **✅ Namespace / derived-name length — RESOLVED.** Per-component DNS-1123 limits for friendliness, plus a
    **deterministic truncate-and-hash fallback** on any derived identifier that would exceed its ceiling —
    namespace (63), **IAM role (64, the tightest** since `Pod-<team>-<product>-<stage>-<service>` carries the
    service), label (63). On overflow, truncate the variable portion to fit and append `-` + the first **6 hex of
    `sha256("<team>/<product>/<stage>/<customer?>/<service?>")`**. Friendly names in the common (short) case;
    always-valid in the edge case. Apply uniformly in the Composition (L2a).

11. **✅ App-level config & secrets — DESIGNED: [ADR-070](../adrs/070-tenant-app-config-and-secrets.md).**
    Portal-first (Backstage form / `platctl`, Backstage the sole broker, write-through) → cloud-native store
    brokered by ESO (**Secrets Manager today**, per-cloud via the seam; **Vault parked behind a trigger**).
    **Config-in-git** (`services.<svc>.config` → ConfigMap) vs **secrets-in-store** (never git → `ExternalSecret`);
    the Service `catalog-info` declares which keys are which. **Prod writes gated** (separation of duties);
    **reveal gated + audited** (symmetric with write, per-key, optional prod step-up — not blanket-hidden).
    **F1 reserves** `services.<svc>.config`/`secrets`; the realization is the **secrets paved-road** phase.

## Migration from v1alpha2

The v1alpha2 `XTenant` ([tenant-api-v2.md](tenant-api-v2.md), the ADR-049 contract) is the predecessor. v3 was
a breaking cutover landed with the rebuild — no in-place migration. Object- and field-level delta:

| v1alpha2 (ADR-049) | v1beta1 (ADR-067) | Change |
| ------------------ | ------------------ | ------ |
| `Tenant` (`XTenant`) | **`Environment` (`XEnvironment`)** | Renamed; re-scoped from `(team, name, environment)` to `(product, stage, customer?)`. |
| `Tenant.environment` (`preprod`/`prod`) | **`Environment.stage`** (`dev`…`prod`) | Renamed; the rung ladder replaces the two-value env; **Stage ≠ Placement** split out. |
| `apps.<app>` (on the Tenant) | **`Product` + `Service`** (first-class) | App split into an owned Product (Domain) and its Services (Components); Repo 1:N Service. |
| image `team-<team>/<app>` | `team-<team>/<product>-<service>` | **Product-scoped** image identity (ADR-067 §7). |
| `Zone` (platform-owned account+cluster) | **retired** → `Environment.isolation` (dial) + `status.placement` | Hard isolation becomes the dial's `cluster`/`account` rungs; coordinates become derived Placement. |
| `Customer` (lightweight placement attribute) | **`Customer`** (first-class consumer) | Promoted; `defaultIsolation` + internal/external; the *default* source of per-customer isolation. |
| `tenancy: pooled\|dedicated(customer)` | `Product.tenancy: pooled\|per-customer` + `Environment.customer` | Tenancy is a Product property; the Customer attaches per prod Environment. |
| `tier` = fixed hardening level | `tier` = **floor**; `Environment.isolation` dials up | `effective = max(tier-floor, chosen)` (ADR-067 §5). |
| `Team.allowedEnvironments` | `Team.allowedStages` | Renamed to the stage ladder. |
| `Team.maxDedicatedZones` | `Team.maxDedicatedIsolation { cluster, account }` | Zone retired → caps on the expensive isolation rungs. |
| `dataServices` (on Tenant) | `Service.resources` + `Resource.isolation` | Moved onto the Service→Resource graph; carries the data-isolation axis. |
| `developerAccess { enabled, group }` | **`AccessGrant`** + `Team.roles` | Team-scoped access replaced by the product-scoped grant model (ADR-068); `team-admin`/`release-approver` roles added. |
| `status.placement { …, zone, namespace }` | `status.placement { cloud, region, account, cluster, namespace }` | `zone` dropped (retired); Stage may map to multiple placements. |

The interim v2 model (`team == tenant`, the v1alpha2 `XTenant`) is retired: the rebuild replaced it with this
schema (`XEnvironment`, `v1beta1`), which is now what's deployed.
