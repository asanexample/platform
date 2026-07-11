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
> platform services stay `Product` + `Environment` + `XEnvironment` — plus two refinements shipping [ADR-099](099-feature-flags-platform-service.md)
> onto the tenant road taught: placement is **resolved** from `(trust, stage)`, not hand-authored, and the composition
> is **selected** by the platform-trust envelope, not conditionally generalized inside the tenant-critical path. Full
> design in [Amendment (2026-07-11): platform-service placement](#amendment-2026-07-11-platform-service-placement--realizing-d2d3d6)
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
(default placement → preprod), landing in a tenant namespace whose per-product `restrict-images` admits only
`team-platform/flagship-*`. Its CNPG Postgres — an upstream `ghcr.io/cloudnative-pg` image — is rejected at
admission, so the service is stuck in-memory. **The blocker was the tenant image *sandbox*, not the preprod
*cluster*.** Run through the *platform* composition — which relies on the cluster-wide `restrict-image-registries`
allow-list, exactly as the hub already does for `backstage-db`/`keycloak-db`/`triage-copilot-db` — CNPG runs
fine on *either* cluster. That reframing decouples two axes D2/D3 had entangled:

### A1 — Composition variant ← trust (the owning Team's envelope)

A platform-Team Product is provisioned by a **platform composition variant** (`environment-platform`),
**selected** by the platform-trust envelope (D6) — *not* a `{{ if platform }}` branch inside the tenant-critical
composition, so the relaxed-image rendering never sits in the path that guards real tenants. It differs from the
tenant composition by: relaxing per-product image-scoping to the cluster-wide registry allow-list (so co-located
CNPG runs), honoring the broader trust envelope, and dropping tenant-only sandbox bits (quota tiers, developer
RBAC, hostname allow-lists) — while **keeping** per-Service Pod Identity, the self-service AWS resources the
tenant model already provisions ([ADR-073](073-self-service-cloud-resources.md)), and the full supply-chain
verify (D5). Selection is keyed on the Team envelope, which is admission-gated and admin-only — a tenant cannot
acquire it, so a tenant cannot escape image-scoping.

### A2 — Cluster ← resolved from `(trust, stage)`, not hand-authored

D2 originally had the Environment *author* `spec.cluster`. This refines it to a **resolved** coordinate (matching
the XRD's own "placement coordinates resolved, never authored"):

```text
cluster = platformTrust
            ? (stage == prod ? hub : preprod)   # platform: prod → hub, else co-locate on preprod
            : (stage == prod ? prod : preprod)  # tenant:   prod → prod, else preprod
```

So **the hub *is* the platform's prod cluster** — platform-prod services join the platform's own production
control planes (Backstage/Keycloak/ArgoCD/Crossplane) there — while **non-prod platform services co-locate with
tenants on preprod**. That co-location is deliberate **dogfooding**: a platform change that breaks tenant
workloads on preprod breaks the platform's own preprod services too — same blast radius, early signal. A
`pinToHub` escape covers the rare service that must *read* cross-cluster hub state (the ADR-082 "blindness"
case); a plain service only *produces* telemetry, which reaches the stack regardless of cluster, so co-location
costs it nothing.

### A3 — No new kinds; only the variant and the cluster fork

Platform services remain `Product` + `Environment` + `XEnvironment` — the same registry, promotion ladder, CI
trust, cosign policy, and self-service AWS as tenants (which is what "treat them the same" actually requires).
Only the composition **variant** (A1) and the destination **cluster** (A2) fork, both driven by signals the model
already carries — the trust envelope and the stage. This is why a parallel `XPlatformProduct`/`XPlatformService`
domain is the wrong shape: it would *split* a shared registry and *duplicate* placement, the trust envelope, and
self-service AWS that already exist. It also **supersedes [ADR-082](082-platform-agent-runtime-xagent.md) D9's
deferred `XPlatformService`**: the non-agent lane is not a new lean kind but the placement-aware `XEnvironment` —
though D9's reusable ns/SA/Pod-Identity partial is still reused, now by the `environment-platform` composition
(A1/A4) rather than a new composite.

### A4 — Topology: federated per-cluster, in-cluster (consistent with ADR-048)

Placing a platform Environment on the hub does **not** reintroduce what [ADR-048](048-federated-per-cluster-crossplane.md)
rejected (a hub Crossplane reaching *across* clusters with remote creds). It follows ADR-048's federated model
exactly: `environment-platform` is deployed **per-cluster as an add-on** and provisions **in-cluster** via
`InjectedIdentity` provider-kubernetes + own-account Pod Identity — no cross-cluster reach, no remote creds, no
provisioning SPOF. A platform service's Environment claim is delivered by GitOps to its **resolved** cluster (A2),
and *that* cluster's local Crossplane reconciles it. This is the same move ADR-048's 2026-06-25 note already
blessed for `XAgent` — the hub gains *another* different, hub-local composition; "agents are simply more [hub
platform infra]," and platform services now are too. Per cluster: the **hub** installs the `XEnvironment` XRD +
`environment-platform` only (no tenant composition — no tenant claims land there); **preprod** installs the tenant
`environment` composition **and** `environment-platform` (co-located platform non-prod); a future **prod** cluster
installs the tenant composition. Composition-selection (A1) picks the right one per claim.

### A5 — Reference service, and one build note

The feature-flag service ([ADR-099](099-feature-flags-platform-service.md)) is to platform *services* what the
triage copilot is to platform *agents* — the first consumer and reference instance. Its dev Environment resolves
to preprod (co-located, CNPG via the platform composition); its prod Environment resolves to the hub. **Build
note:** no CNPG runs on the preprod cluster today, so its cluster-wide `restrict-image-registries` must add
`ghcr.io/cloudnative-pg/*` before the platform composition can host a database there (a one-line policy change).

## Alternatives considered

- **A parallel platform-services road** (this ADR's earlier draft; and the later `XPlatform*`-kinds sketch).
  Rejected — duplication, and it re-creates the platform-vs-tenant split. The 2026-07-11 amendment shows the
  faithful "treat them the same" is the *shared* `Product`/`Environment` model with a resolved placement + a
  selected composition variant, not a parallel domain.
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
