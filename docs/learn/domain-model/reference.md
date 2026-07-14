# Domain model — reference

A working summary of the domain model. [The orientation](orientation.md) walks through the tree-and-grid
model — ownership is a tree, deployment is a grid — from scratch. The normative schema (every field, type,
and default) is [platform-domain-api.md](../../architecture/platform-domain-api.md).

## The nouns

| Noun | What it is | Authored by | Represented as |
| --- | --- | --- | --- |
| **Team** | The owner: an SSO group + an **envelope** that bounds everything below it. Owns no infra itself. | Platform (admin) | `gitops/teams/<team>.yaml` → projected `Team` CR |
| **Product** | A deployable a team builds; maps to exactly **one repo**. | Team lead (self-service) | `gitops/products/<team>/<product>.yaml` → projected `Product` CR |
| **Service** | A single running component (web, api). A Product owns N; a repo sources N (monorepo). | Developer | repo-native `catalog-info.yaml` (not a control-plane CR) |
| **Environment** | A `(Product × Stage[, × Customer])` instance = **one namespace**. The unit of deployment. | Team lead / dev (self-service) | `gitops/environments/**` → `XEnvironment` claim |
| **Customer** | An external (or internal) consumer of a Product; adds a coordinate to per-customer prod environments. | Platform / sales ops | registry entry (no projected CR yet) |

## The relationships

```text
Team ──owns──▶ Product ──owns──▶ Service ◀──sources(1:N)── Repo   (one repo : ONE product)
  │              └──realized-at-a-Stage-as──▶ Environment = (Product × Stage[, × Customer])
Developer ──member-of──▶ Team (implicit access to its Products)
Developer ──granted──▶ Product (explicit, cross-team — an AccessGrant)
```

- **Ownership is a tree** (Team → Product → Service): exactly one owner each.
- **Access is many-to-many** (Developer ↔ Product): a cross-team `AccessGrant` gives access without
  ownership. Kept on a separate edge from ownership *by design*.
- **Identity is per-repo; artifacts are per-service.** One repo maps to one Product; the image identity is
  product-scoped: `team-<team>/<product>-<service>`.

## Agents (`XAgent`) — a second deployment shape

A Product can deploy as an **agent** instead of an Environment. `XAgent` is a sibling claim to
`XEnvironment` — same `team` / `product` ownership — but hub-placed and shaped for an AI agent: a `model`,
an `autonomy` limit (`propose-only` = read + suggest, never act), a `trigger`, and `awsPermissions`, with
no stage/namespace grid. The reference agent is `triage-copilot` (`gitops/agents/`, owned by team
`platform`). Full treatment belongs to the **agentic-platform** module (planned).

## Stage vs Placement

- A **Stage** (`dev` / `test` / `staging` / `uat` / `prod`) is a *promotion rung* a developer reasons
  about — **not** a location.
- A **Placement** (cloud / region / account / cluster) is where it physically lands — *derived* by the
  platform, written to `status`, never authored. One Stage can map to several Placements (HA/DR). Today
  every Environment resolves to the single workload cluster.

## Naming (all derived from the coordinates)

| Derived name | Pattern | Example |
| --- | --- | --- |
| Namespace / Environment name | `<team>-<product>-<stage>` (`…-<customer>-<stage>` per-customer) | `acme-shop-dev` |
| Image / [ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html) path | `team-<team>/<product>-<service>` | `team-acme/shop-web` |
| Generated host | `<product>-<team>-<stage>.<baseDomain>` | `shop-acme-dev.preprod.aws.refplat.org` |
| [Pod-Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) role | `Pod-<team>-<product>-[<customer>-]<stage>-<service>` | `Pod-acme-shop-dev-web` |

Any derived identifier that would exceed its length ceiling (namespace 63, IAM role 64) is
truncate-and-hashed deterministically — friendly in the common case, always valid in the edge case.

## The Team envelope

The bound on every Product/Environment a Team may author — enforced at
[admission](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
([Kyverno](https://kyverno.io/docs/) on the projected `Team` CR). Team `acme`'s, live:

```yaml
envelope:
  allowedTiers: ["standard"]                         # an Environment tier outside this set → rejected
  allowedStages: ["dev","test","uat","staging","prod"]
  quotaCap: { cpu: "8", memory: 16Gi, pods: 40 }     # per-Environment ceiling AND aggregate cap
  budget: { monthlyUSD: 2000 }                        # cost guardrail
  maxDedicatedIsolation: { cluster: 0, account: 0 }  # 0 = pooled only (no dedicated cluster/account)
  resources: { allowedEngines: ["s3","sqs","sns","dynamodb"], maxPerEnvironment: 10 }
```

- **Stateless, hard-enforced at admission:** `tier ∈ allowedTiers`, `stage ∈ allowedStages`,
  `quota ≤ quotaCap`, `residency ⊆ allowedLocations`, image registry ⊆ the product scope.
- **Aggregate, report-first (designed, not yet built):** sum of environment quotas ≤ cap,
  dedicated-isolation in use ≤ `maxDedicatedIsolation` — a rollup controller is *planned* to alert on
  these (the stateless per-Environment checks above are live; the aggregate tier is not — nothing writes
  `Team.status` today), and would hard-enforce only if a team actually pushes a cap.

## Tier is a floor, not a level

A `tier` (`standard` / `elevated` / `pci` / `hipaa`) names a **profile** bundling isolation + recovery +
availability. It sets a **minimum** — a regulated tier *forces* stronger isolation; anyone may dial *up*.
Effective isolation = `max(tier-floor, chosen)`. Recovery/availability are derived from the tier, never
re-declared.

## Gotchas

- **`team` is carried on the Environment, not just derived.** The `XEnvironment` claim repeats `team`
  (validated `== Product.team`) because the namespace, the Pod-Identity role, and the envelope policy all
  need it, and a Crossplane go-template can't cross-CR-lookup the Product. Denormalized on purpose.
- **One repo : one Product** (but one Product : many Services). A monorepo is fine; a repo spanning two
  Products is not — image identity would be ambiguous.
- **The deployed digest is *not* in the Environment claim.** It lives in a separate `Release` record,
  because a digest changes every build and the human-authored claim shouldn't churn. The claim
  declares *what* runs; the Release says *which image*.
- **`Customer` only attaches at prod/uat** for `per-customer` products; it's forbidden on
  dev/test/staging (those stay internal/pooled).

## Source of truth

- [Platform Domain API](../../architecture/platform-domain-api.md) — the normative schema (every field).
- Registries: [`gitops/teams`](https://github.com/asanexample/platform/tree/main/gitops/teams),
  [`gitops/products`](https://github.com/asanexample/platform/tree/main/gitops/products),
  [`gitops/environments`](https://github.com/asanexample/platform/tree/main/gitops/environments).
- Related skill: `environment-onboarding` (authoring these registry files).
- Shared substrate terms (namespace, admission, custom resource, …): the [portal glossary](../glossary.md).
