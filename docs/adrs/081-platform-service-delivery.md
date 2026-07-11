# ADR-081: Platform-Team Products on the One Delivery Road — Unified Provisioning + Per-Environment Placement

**Status:** Proposed (2026-06-24) · **Runtime-placement decision (D2/D3) superseded for platform agents by [ADR-082](082-platform-agent-runtime-xagent.md) (2026-06-25)** · **D2/D3/D6 realized for non-agent platform services (2026-07-11, see Amendment below)**

> **Amendment (2026-06-25).** This ADR conflated two separable concerns under "one road": **supply-chain/registry
> unification** (D1, D4, D5 — one `Product`/`Release` registry, one build→sign→promote backbone, one OIDC/ECR story) and
> **runtime placement** (D2, D3, D6, D7 — provisioning a platform product via the *tenant* `XEnvironment` Composition,
> generalized for placement + a `platformTrust` envelope). **The supply-chain unification was right and stands for all
> workloads, platform and tenant alike.** The runtime unification was the over-correction: it forced a
> platform-infrastructure agent through the tenant Environment model, and the agent landed on a workload cluster (preprod),
> blind to its hub-resident observability. [ADR-082](082-platform-agent-runtime-xagent.md) fixes only the runtime half:
> **runtime forks by workload type** — tenant → `XEnvironment` Composition on a workload cluster (unchanged); platform agent →
> a purpose-built `XAgent` Composition on the hub. D2/D3/D6/D7 below are **superseded for platform agents** by that lane; the
> `platformTrust` envelope becomes vestigial for the agent. D1/D4/D5 (supply chain) are unchanged. This realizes the
> "declarative `Agent` CRD (a future layer above this, ADR-074)" that D7/Scope explicitly left out of scope.

<!-- -->

> **Amendment (2026-07-11).** ADR-082 forked *agents* off D2/D3; this finishes the branch the 2026-06-25 amendment
> left open — **non-agent platform services** (a control plane, a UI, an internal API; the feature-flag service
> [ADR-099](099-feature-flags-platform-service.md) is the reference). It **realizes D2/D3/D6 with no new kinds** —
> platform services stay `Product` + `Environment` + `XEnvironment`. The realized fork is a **fail-safe image-sandbox
> exemption** for platform-owned Teams (so a service can co-locate a database like CNPG Postgres); the
> `(trust, stage) → cluster` placement resolver is the target model but **not yet built** (dev already lands on
> preprod). Full design + as-built notes in [Amendment (2026-07-11): platform-service placement](#amendment-2026-07-11-platform-service-placement--realizing-d2d3d6)
> below; it supersedes the exploratory `XPlatformService`/`XPlatformProduct` direction (a new kind reinvents placement,
> the trust envelope, and self-service AWS this model already has).

## Context

Internally-developed, platform-owned services and agents had no standard delivery path: backstage and the ARC runner are
bespoke Terragrunt-Helm one-offs, and [ADR-080](080-triage-copilot.md)'s triage copilot was on track to be a third. The
first instinct (an earlier draft of this ADR) was a *parallel* "platform-services" GitOps road alongside the tenant one.

That was the wrong call. **A parallel road is duplication** — a second ApplicationSet, a second registry, a second
promote/validation story — and it re-introduces exactly the platform-vs-tenant split the platform is trying to erase.
Platform-team products are *more* trusted than dev-team products, **but not by much**, and they deserve the same
structure, gating, validation, and promotion as everyone else. There should be **one delivery road**.

## Decision

**The platform team is a first-class Team, and its products flow through the entire tenant delivery machinery** — the
`Product`/`XEnvironment`/`Release` registries, the Crossplane Environment **Composition**, the per-Product
`ApplicationSet`, `promote.yml`, the gitops Gate, and the Kyverno envelope — with exactly **two generalizations**:

1. **Placement** is a per-**Environment** property (which cluster a deployment lands on), realizing the long-degenerate
   `Deployment → Placement` of [ADR-067](067-idp-domain-model.md).
2. A **platform-trust envelope** lets the platform Team declare what tenants can't (cluster-scoped read, the Bedrock
   action, broader namespaces) — but it is still an envelope, still admission-gated.

There is **one provisioning path for everyone.** A platform product is provisioned by the same Composition that
provisions tenant products, wherever it lands.

## Design

### D1 — `platform` is a Team

`gitops/teams/platform.yaml` is a normal `Team` with a **platform-trust envelope** (D6). Its products live at
`gitops/products/platform/<product>.yaml`; the triage copilot is the **reference product**.

### D2 — Placement is a per-Environment property (the multi-cluster seam)

The `Environment` declares its target cluster: `spec.cluster: platform | preprod | prod` (default **`preprod`** — today's
behavior, so nothing existing changes). The per-Product ApplicationSet resolves `destination.name` from it against
ArgoCD's registered clusters; the Composition provisions on that cluster. **Placement is not a platform concept** — any
team's environment can set it — it just *happens* that the triage copilot's first Environment targets `platform`. A later
platform agent might target `preprod` or `prod`; a tenant could one day multi-cluster too. No platform special-case.

### D3 — One Composition provisions everything

A platform product's `XEnvironment` is provisioned by the **same Composition** as tenants — namespace, ResourceQuota,
per-Service identity, ECR — generalized to (a) be **placement-aware** (provision on `spec.cluster`) and (b) honor the
**platform-trust envelope**. No platform-specific Terragrunt provisioning units.

### D4 — Identity via the existing per-Service policyStatements

The agent's `bedrock:InvokeModel` is declared as a normal `services.<svc>.permissions.aws.policyStatements` entry and
minted as a per-Service **EKS Pod Identity** role by the Composition — the same mechanism tenant services use for AWS
access. Bedrock is not in the deny-set ([ADR-062](062-self-service-tenant-provisioning.md) §4), so it passes the envelope
validator unchanged. **No bespoke identity unit.**

### D5 — Supply chain via the shared backbone

The agent is a thin caller of `asanexample/trusted-ci/build-sign.yml` + `slsa-provenance.yml` + `promote.yml` like any
app ([ADR-050](050-shared-build-sign-reusable-workflow.md)/[ADR-071](071-digest-promotion-via-control-plane.md)). Its
image is the tenant-shaped `team-platform/<product>-<svc>`, built by the registry-derived per-Product OIDC role,
cosign-signed, SBOM'd, and digest-promoted into `gitops/releases/platform/<product>/<stage>.yaml`. **No dedicated ECR or
OIDC role; no bespoke `build.yml`.**

### D6 — The platform-trust envelope (the "more or less")

The platform Team's envelope is broader than a tenant's — it may allow **cluster-scoped read RBAC** (an observability
agent reads across namespaces; tenants are namespace-scoped), the **Bedrock action**, and platform-appropriate stages —
but it is the **same envelope mechanism**, declared in `gitops/teams/platform.yaml`, validated at admission. Trust is a
*parameter* of the one model, not a second model.

### D7 — This supersedes the parallel-road approach

The earlier `gitops/platform-services` registry + separate ApplicationSet (and the platform-specific Pod Identity / ECR /
OIDC units merged as #685/#686/#688) are **withdrawn** in favor of the single road: the agent becomes a `platform`-team
Product. backstage / gha-runner MAY migrate onto it later (out of scope).

## Scope

- **In:** `platform` as a Team; per-Environment Placement (the ApplicationSet + Composition generalization); the
  platform-trust envelope; the triage copilot re-expressed as a `platform`-team Product (reference instance).
- **Out (for now):** migrating backstage / gha-runner; registering the prod cluster as an ArgoCD destination (done when a
  prod-targeted Environment first needs it); a declarative `Agent` CRD (a future layer above this, ADR-074).

## Consequences

- **One road, no platform exceptions** — same registries, gating, validation, promotion, and provisioning for platform
  and tenant products alike. Onboarding any platform service is a Team-scoped Product, identical to a tenant Product.
- **The cost is real: the Composition must generalize** — placement-awareness (provision on a named cluster, not just
  preprod) and the platform-trust envelope are non-trivial changes to tenant-critical infra and must be done carefully.
- **Today's merged work folds away** (#685/#686/#688) — cheaply, since nothing was applied. The agent's identity, image,
  delivery, and provisioning all collapse onto the standard path.
- Placement is a genuinely useful capability beyond platform — it is the start of real multi-cluster delivery.

## Amendment (2026-07-11): platform-service placement — realizing D2/D3/D6

The 2026-06-25 amendment split platform workloads into two runtime branches and only built one: **agents** →
`XAgent` on the hub ([ADR-082](082-platform-agent-runtime-xagent.md)). The **service** branch — a plain
platform-owned service, *not* a model-driven agent — was left on the default tenant road, and shipping the
feature-flag service ([ADR-099](099-feature-flags-platform-service.md)) there exposed both why that default is
wrong and what the finished design is.

**What broke, and the correct read.** Flagship's Environment used the tenant Composition on a workload cluster
(default placement → preprod), landing in a tenant namespace governed by **two** environment image policies — the
per-product `restrict-images` (Composition-emitted) *and* the environment image *floor* `restrict-image-registries`
(platform-ECR-only, scoped to any env namespace). Its CNPG Postgres — an upstream `ghcr.io/cloudnative-pg` image —
is rejected by **both**, so the service is stuck in-memory. **The blocker was the tenant image *sandbox*, not the
preprod *cluster*.** (Verified: the same CNPG image runs on the hub for `backstage-db`/`keycloak-db`/`triage-copilot-db`
— those are *non-environment* namespaces the floor never watches.) The fix is to make a **platform-owned** Team's
Environment exempt from that image sandbox. That decouples two axes D2/D3 had entangled:

### A1 — Image-sandbox exemption ← trust (a fail-safe conditional, not a second composition)

> **As built ([#1315](https://github.com/asanexample/platform/pull/1315)).** The design first reached for a *second*
> Composition (`environment-platform`) selected by a `platformTrust` label. Two build facts overruled that: the
> Environment Composition is a **single monolithic raw go-template** (shipped via `.Files.Get`, opaque to Helm — no
> shared partial exists; ADR-082 D9's "reusable partial" turned out aspirational), so a second Composition would
> **duplicate ~1000 lines of security-critical netpol/IAM**; and there is **no composition-selection hook** on the
> XRD or the hand-authored claims to pick between two Compositions. So the exemption is a **fail-safe conditional in
> the one Composition**, gated on `$isPlatformTrust` (an explicit team allow-list — `["platform"]` — today).

A platform-trust Environment is exempt from the tenant image *sandbox*, and **only** that:

- The Composition does **not** emit the per-product `restrict-images` ClusterPolicy, and marks the namespace
  `platform.refplat.org/trust: platform`.
- The environment floor `restrict-image-registries` **excludes** namespaces carrying that marker (a new, fail-safe
  policy exemption — inert unless the marker is present).

Everything else is **kept**, because it is compatible with a platform service (verified against Flagship by render
test): the ResourceQuota, per-Service Pod Identity, self-service AWS ([ADR-073](073-self-service-cloud-resources.md)),
cluster-read RBAC, the route-hostname allow-list, and the full cosign supply-chain verify (D5 —
`verify-images-product` is image-glob-scoped to `team-platform/<product>-*`, so the service's own image is still
verified; the co-located CNPG image is admitted by being *unmatched*). **Fail-safe by construction:** default (any
team not in the allow-list) = the full tenant sandbox; only the Composition sets the marker, only for a platform-trust
Team, so a tenant cannot acquire it. The allow-list is the pragmatic v1 signal for the (now-removed, ADR-082)
**platformTrust envelope** (D6), which is re-added when a *second* platform Team needs the lane.

### A2 — Cluster ← resolved from `(trust, stage)` — the target model, not yet built

The intended placement is a **resolved** coordinate (matching the XRD's "placement coordinates resolved, never
authored"):

```text
cluster = platformTrust
            ? (stage == prod ? hub : preprod)   # platform: prod → hub, else co-locate on preprod
            : (stage == prod ? prod : preprod)  # tenant:   prod → prod, else preprod
```

So **the hub *is* the platform's prod cluster**, while **non-prod platform services co-locate with tenants on
preprod** — deliberate **dogfooding** (a platform change that breaks tenant workloads on preprod breaks the
platform's own preprod services too). A `pinToHub` escape covers the rare service that must *read* cross-cluster hub
state (the ADR-082 "blindness" case); a plain service only *produces* telemetry, so co-location costs it nothing.

**Not built yet, and not needed for the first consumer.** There is no `(trust, stage) → cluster` resolver today —
destinations are static per-unit Terraform variables (`cluster_server`/`hub_cluster_server`) and claims are
hand-authored. Flagship *dev* already lands on preprod via the existing default, so the resolver is deferred until a
platform **prod** Environment first needs the hub — the same "built when a real consumer needs it" discipline
ADR-082 D9 used.

### A3 — No new kinds; the sandbox exemption is the only realized fork

Platform services remain `Product` + `Environment` + `XEnvironment` — the same registry, promotion ladder, CI
trust, cosign policy, and self-service AWS as tenants (what "treat them the same" actually requires). Today the
**only** realized fork is the image-sandbox exemption (A1); the cluster fork (A2) is deferred. A parallel
`XPlatformProduct`/`XPlatformService` domain is the wrong shape — it would *split* a shared registry and *duplicate*
placement, the trust envelope, and self-service AWS that already exist. This also **supersedes
[ADR-082](082-platform-agent-runtime-xagent.md) D9's deferred `XPlatformService`**: the non-agent lane is the
`XEnvironment`, not a new lean kind.

### A4 — Topology: federated per-cluster, in-cluster (consistent with ADR-048)

A platform Environment is provisioned by the **same per-cluster, in-cluster** Crossplane every Environment uses
([ADR-048](048-federated-per-cluster-crossplane.md)) — `InjectedIdentity` provider-kubernetes, own-account Pod
Identity, no cross-cluster reach, no remote creds, no SPOF. The claim is GitOps-delivered to the cluster it lands
on, and *that* cluster's local Crossplane reconciles it. Putting one on the hub (for platform *prod*) is "more
hub-local platform infra," exactly as ADR-048's 2026-06-25 note blessed for `XAgent`. Today platform services land
on **preprod**, which already runs the Environment control plane; the hub gains it if/when a platform-prod
Environment is placed there (A2). **One prerequisite the build surfaced:** the **CNPG operator was hub-only**, so a
co-located database on preprod needs the operator there — [#1315](https://github.com/asanexample/platform/pull/1315)
adds a preprod `cloudnative-pg` unit.

### A5 — Reference service + what shipped

The feature-flag service ([ADR-099](099-feature-flags-platform-service.md)) is to platform *services* what the
triage copilot is to platform *agents* — the first consumer and reference instance; its dev Environment stays on
preprod. Shipped in [#1315](https://github.com/asanexample/platform/pull/1315): the fail-safe Composition exemption
(A1), the floor policy exemption, the preprod `cloudnative-pg` unit, and render tests asserting the platform-trust
path *and* the fail-safe tenant default. Remaining: Flagship's CNPG `Cluster` + `DATABASE_URL` bundle, and the gated
preprod applies (`cloudnative-pg` → `policy` → `crossplane` → Flagship).

## Alternatives considered

- **A parallel platform-services road** (this ADR's earlier draft; and the later `XPlatform*`-kinds sketch).
  Rejected — duplication, and it re-creates the platform-vs-tenant split. The 2026-07-11 amendment shows the
  faithful "treat them the same" is the *shared* `Product`/`Environment` model with a fail-safe image-sandbox
  exemption for platform-owned Teams (and, later, resolved placement), not a parallel domain.
- **Unify governance/delivery but keep platform-specific provisioning units.** Rejected — the moment a platform product
  targets preprod/prod it needs provisioning *there*, which is exactly what the Composition already does; platform units
  quietly re-introduce the split.

## Related

- [ADR-067](067-idp-domain-model.md) — the Team→Product→Environment model + the `Placement` concept this realizes.
- [ADR-069](069-delivery-source-of-truth-product-environment.md) / [ADR-071](071-digest-promotion-via-control-plane.md) —
  the delivery source-of-truth + digest promotion the platform Team reuses unchanged.
- [ADR-062](062-self-service-tenant-provisioning.md) — the policyStatements deny-set the agent's Bedrock identity passes (D4).
- [ADR-074](074-agentic-workloads-platform.md) — agents as a workload class; a future declarative `Agent` CRD above this road.
- [ADR-080](080-triage-copilot.md) — the triage copilot, this road's reference *agent*.
- [ADR-099](099-feature-flags-platform-service.md) — the feature-flag service, this road's reference *service* (the 2026-07-11 amendment).
- [ADR-073](073-self-service-cloud-resources.md) — the self-service AWS resources a platform service inherits unchanged (amendment A1).
- [ADR-048](048-federated-per-cluster-crossplane.md) — the federated per-cluster Crossplane topology the platform composition follows (amendment A4).
