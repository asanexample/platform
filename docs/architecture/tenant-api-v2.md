# Tenant API v2 — Team / Tenant / Zone / Customer Schemas

The finalized, normative object schemas for the multi-tenancy model of
[ADR-049](../adrs/049-tenant-model-team-tenant-zone.md). ADR-049 sets the *direction* (separate ownership
from isolation from placement); this document is the *contract* — the concrete field names, types, defaults,
enums, and required/optional status that the rebuild implements and that the
[ADR-053](../adrs/053-identity-and-cross-system-authorization-strategy.md) access-model-as-code generators
read from.

> **Status: design-stage, normative-on-paper.** These schemas land with the **planned rebuild**, not as an
> in-place migration (ADR-049). They supersede the v1alpha1 `XTenant` schema documented in
> [crossplane-tenant-api.md](crossplane-tenant-api.md) (the current, interim contract). Where this doc and the
> live `xrd.yaml` disagree, the live file is what's deployed today and this doc is the target.

Finalizing these schemas is the first implementation step of the rebuild: the Keycloak group taxonomy, the
per-system RBAC generators, and the Backstage permission policy (#197) all read from the **Team envelope**
defined here (ADR-053, decision 3).

## Conventions

- **API group / version.** All Kubernetes-projected objects use `platform.refplat.org/v1alpha2`. The Tenant
  XR bumps from `v1alpha1` → `v1alpha2` (breaking; see [Migration](#migration-from-v1alpha1)).
- **Cloud-neutrality is a hard rule for author-facing fields.** A developer-authored object (Tenant, and the
  author-facing parts of Team/Customer) **never** names a cloud, region, account, cluster, or namespace.
  Those are *derived by placement* and written to `status`. The single deliberate exception is
  `Tenant.spec.apps.<app>.permissions`, which is **explicitly cloud-keyed** (`permissions.aws.…`) while the
  identity binding it attaches to (`serviceAccount`) stays neutral. *How* this neutral claim is realized on more
  than one cloud — a shared XRD with one Composition per cloud (neutral K8s core + per-cloud identity/registry
  overlays), selected by placement — is [ADR-058](../adrs/058-per-cloud-tenant-composition-strategy.md).
- **Location, not region.** A *location* is a `(cloud, region)` pair. A *jurisdiction* (`"eu"`, `"us"`) is a
  named set of acceptable locations. Author-facing fields take a jurisdiction or an exact `cloud:region`
  string; they never take a bare region. This is what makes data residency and multi-cloud the same
  mechanism.
- **Two authorization planes, one model** (ADR-049 / ADR-053). The **envelope plane** (`tier ∈ allowedTiers`,
  quota, allowed envs/locations) is enforced at *admission* by Kyverno on the `Tenant` CR. The **user-RBAC
  plane** (`environment × tier` developer posture) is propagated to each system by the ADR-053 generators.
  Both derive from the **Team** object below.
- **Reserved fields.** Some fields below are marked **🔒 Reserved (deferred)** — they are part of the v2
  schema so the API is forward-compatible, but the platform does not yet *provision* them (each activates when
  its paved road / control is built). They are modeled now because the rebuild **bakes the schema**: adding a
  top-level dimension after the fact is a breaking change; reserving an optional field is not. A 🔒 field is
  inert until its backing control ships.
- **Ownership of authorship** (who may write each object):

  | Object | Authored by | Representation |
  | ------ | ----------- | -------------- |
  | **Team** | Platform team (a Team is granted) | Registry → Backstage `Group`; **projected as a `Team` CR** per cluster for admission |
  | **Tenant** | Team lead / developer (self-service) | Crossplane `XTenant` XR (`v1alpha2`), GitOps-delivered |
  | **Zone** | Platform team only | Terragrunt-provisioned (pooled) / vended (dedicated); registry record |
  | **Customer** | Platform team / sales ops | Registry → Backstage entity |

## Tier profiles — isolation · recovery · availability

A `tier` is a reference to a platform-defined **profile**, not a set of primitives (ADR-049). v1 treated the
profile as *isolation strength* only. v2 makes the profile bundle **three** postures, all resolved by the
platform from the single `tier` a developer names — preserving "developers pick the level, the platform
decides what the level means":

| Posture | What it sets | Detail lives |
| ------- | ------------ | ------------ |
| **isolation** | compute / account / cluster / network separation | ADR-049 isolation spectrum |
| **recovery** | RPO, RTO, backup retention; for regulated, the *minimum data-retention hold* before destruction | this profile · 🔒 backup/DR system deferred |
| **availability** | AZ spread + target SLO | this profile |

Default matrix (illustrative — the authoritative values live with the platform-owned profile definitions, not
the claim):

| tier | isolation | recovery (RPO / RTO / retention) | availability |
| ---- | --------- | ------------------------------- | ------------ |
| `standard` | namespace (PSA + Kyverno) | best-effort / next-business-day / 7d | multi-AZ, 99.5% |
| `elevated` | + dedicated node pool | 24h / 4h / 30d | multi-AZ, 99.9% |
| `pci` / `hipaa` | dedicated cluster + account | ≤1h / ≤1h / regime-mandated (e.g. 7y) | multi-AZ, 99.95%, DR-tested |

Two consequences for the schema:

- **Recovery and availability are derived from `tier`** — a Tenant never re-declares them. A
  `dataServices.<n>.backup` override may only *strengthen* the default, never weaken it.
- A tenant's availability **cannot exceed what the platform region provides.** The platform control plane is
  **single-region today**; multi-region platform resilience is an *out-of-schema* concern (an ADR, not a
  tenant field). The tier's availability target is honest only up to that ceiling — stated here so the limit
  is explicit, not implied.

## Object 1 — Team

The **owner**: an SSO/Keycloak group plus an **envelope** that bounds every Tenant it owns. A Team has no
namespace of itself; it owns N Tenants. The envelope is the single source the ADR-053 generators compile
outward.

Two representations of the same record:

- **Canonical record** — full Team definition (registry today, Backstage `Group` end-state). Source of truth.
- **Projected `Team` CR** — a minimal, read-only mirror of the envelope, projected onto each cluster so
  Kyverno admission can read it when validating a `Tenant`. Carries only what admission needs.

### Canonical Team record

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `name` | yes | string | — | Team key (kebab-case). Drives `Team.metadata.name`, the SSO/Keycloak group, and the `<team>-` namespace prefix. |
| `displayName` | — | string | `name` | Human label (Backstage). |
| `ssoGroup` | yes | string | — | The Identity Center group / Keycloak group this Team maps to. The root of both authorization planes. |
| `developerGroup` | — | string | `ssoGroup` | Default group granted developer access to the Team's Tenants. A Tenant may override it (required for regulated prod). |
| `costCenter` | — | string | — | Billing / showback attribution. |
| `contacts` | — | `[]string` | `[]` | Owner emails (Backstage `spec.owner`, escalation). |
| `envelope` | yes | object | — | The bound on every Tenant the Team may author. See below. |

`envelope`:

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `allowedTiers` | yes | `[]enum` | — | Subset of `standard` / `elevated` / `pci` / `hipaa` the Team may request. A `Tenant.spec.tier` outside this set is **rejected at admission**. |
| `allowedEnvironments` | yes | `[]enum` | — | Subset of `preprod` / `prod`. |
| `allowedLocations` | — | `[]string` | `["*"]` | Jurisdictions/locations the Team's Tenants may sit in. A Tenant's `residency.allowedLocations` must be a **subset**. `["*"]` = anywhere the platform operates. |
| `quotaCap` | yes | object | — | Per-tenant ceiling AND aggregate cap. `cpu`/`memory`/`pods` (same shape as `Tenant.spec.quota`). A single Tenant's quota is checked ≤ cap at admission (stateless); the **sum** across the Team's Tenants is checked by the report-first rollup controller (stateful). |
| `maxDedicatedZones` | — | integer | `0` | How many dedicated (per-customer) zones the Team may occupy. `0` = pooled only. Aggregate check (report-first). |

### Projected `Team` CR

Cluster-scoped mirror, written by the platform's model-as-code sync (not by developers). Kyverno reads it
during `Tenant` admission. Only the admission-relevant envelope subset is projected — no contacts, no cost
center.

```yaml
apiVersion: platform.refplat.org/v1alpha2
kind: Team
metadata:
  name: payments                       # = canonical Team.name
spec:
  ssoGroup: payments-eng               # for RBAC generation cross-checks
  envelope:
    allowedTiers: [standard, elevated, pci]
    allowedEnvironments: [preprod, prod]
    allowedLocations: ["eu", "us"]
    quotaCap: { cpu: "64", memory: 128Gi, pods: 400 }
    maxDedicatedZones: 2
# status: { tenantCount, aggregateQuota, dedicatedZonesInUse }   (written by the rollup controller)
```

## Object 2 — Tenant

The **developer-authored contract**: a logical isolation unit owned by a Team, realized per environment. Pure
**intent + constraints** — it declares *what* it needs, never *where* it lands. Placement resolves it to a
Zone and writes the concrete coordinates to `status`.

`apiVersion: platform.refplat.org/v1alpha2`, `kind: XTenant`, **cluster-scoped** (Crossplane v2 XR — creating
one requires cluster RBAC, the S1 self-provisioning gate). Logical identity = `(team, name, environment)`;
`metadata.name` is conventionally `<name>-<environment>`.

### spec

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `team` | yes | string | — | Owning Team key → envelope + SSO group. Must reference an existing `Team`. |
| `name` | yes | string | — | Tenant name within the Team (e.g. `payments-api`). `(team, name)` is unique; namespace = `<team>-<name>`. |
| `environment` | yes | enum | — | `preprod` / `prod`. Must be in the Team's `allowedEnvironments`. |
| `tier` | — | enum | `standard` | `standard` / `elevated` / `pci` / `hipaa` — a reference to a platform hardening **profile**, not primitives. Must be in the Team's `allowedTiers`. |
| `tenancy` | — | object | `{ mode: pooled }` | `mode: pooled \| dedicated`; `customer` **required iff** `mode: dedicated` (→ a `Customer`). Dedicated consumes one of the Team's `maxDedicatedZones`. |
| `residency` | — | object | `{ allowedLocations: ["*"] }` | `allowedLocations: []string` — **hard, attested** placement constraint (jurisdiction or `cloud:region`). Must be ⊆ the Team's `allowedLocations`. Placement fails (not silently relaxes) if no Zone satisfies it. |
| `quota` | — | object | tier profile default | `cpu`/`memory`/`pods` (+ optional `services`/`loadbalancers`/`pvcs`/`storage`). Validated ≤ the Team's `quotaCap`. |
| `domains` | — | `[]object` | `[]` | ADDITIONAL route hostname aliases (`{ host, canonical, dns }`) — the authoritative hostname field (ADR-061, supersedes the earlier `hostnames` string list). The generated `<app>-<team>.<baseDomain>` host is implicit and never declared. The Composition unions these with the generated host into `restrict-route-hostnames` and writes per-host `status.domains` state (tier-1/2 → Active; external → Pending). |
| `apps` | — | map | `{}` | `<app> → AppSpec`. Delivery + per-app identity + per-app permissions, unified. See below. |
| `developerAccess` | — | object | `{ enabled: true }` | `enabled: bool`; `group: string` (override the Team `developerGroup`). The override is **required** for regulated (`pci`/`hipaa`) prod. Names only *who* — the *posture* is derived (see [Developer access](#developer-access-posture)). |
| `dataServices` | — | map | `{}` | 🔒 **Reserved.** `<name> → DataServiceSpec` — cloud-neutral stateful dependencies (DB / cache / object store / stream). Realized data **inherits the Tenant's `residency`** — placement validates the data's location ⊆ `allowedLocations`, closing the *compute-residency-without-data-residency* gap — and the tier's recovery posture. Provisioning lands with the data paved-road (#106/#107). |
| `encryption` | — | object | derived from `tier` | `keyCustody: platform-managed \| customer-managed \| customer-hosted`. Defaults `platform-managed`; regulated / dedicated may default to `customer-managed` (a dedicated CMK). 🔒 BYOK/HYOK realization deferred; the field reserves the contract. |
| `lifecycle` | — | object | `{ phase: active }` | `phase: active \| suspended \| decommissioning`. Setting `decommissioning` triggers ordered teardown → data destruction (or regime-mandated retention hold) → exit attestation, written to `status`. The **exit** counterpart to onboarding. |

`apps.<app>` (AppSpec):

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `repo` | yes | string | — | Git repo with the app's K8s manifests (ArgoCD source + the app's ECR repo `team-<team>/<app>`). |
| `repoPath` | — | string | `k8s/<environment>` | Path to the manifest dir. |
| `preview` | — | boolean | `false` | Create a PR-preview ApplicationSet (ADR-032). |
| `serviceAccount` | — | string | — | Named SA the app's pods run as. A **cloud-neutral** identity is minted and bound to `(namespace, serviceAccount)` (AWS today = a Pod Identity association → `Pod-<team>-<app>`). Must not carry an IRSA annotation (backstop). |
| `permissions` | — | object | `{}` | **Cloud-keyed** grants attached to `serviceAccount`. `permissions.aws.policyStatements: []` (sid/effect/actions/resources — same shape as v1alpha1 `aws.policyStatements`), capped by the deny-escalation boundary. Per-app, not per-team — the fix for the single-`Pod-team` limitation. |

`dataServices.<name>` (DataServiceSpec) — 🔒 Reserved:

| Field | Required | Type | Default | Purpose |
| ----- | -------- | ---- | ------- | ------- |
| `kind` | yes | enum | — | `relational` / `cache` / `objectstore` / `stream` — the cloud-neutral *category*, never a product. |
| `engine` | — | string | — | Interface hint (`postgres`/`mysql`/`redis`/`kafka`) — the API contract the app codes against, not the cloud implementation that satisfies it. |
| `class` | — | string | tier default | Platform-defined size/durability class (a reference, like `tier`). |
| `serviceAccount` | — | string | — | The app SA granted access — binds to per-app identity, mirroring `apps.<app>.serviceAccount`. |
| `backup` | — | object | tier recovery default | Optional override that may only **strengthen** (longer retention / tighter RPO) the tier's recovery posture. |

### status (derived by placement — never authored)

| Field | Type | Purpose |
| ----- | ---- | ------- |
| `placement.cloud` / `.region` / `.account` / `.cluster` / `.zone` / `.namespace` | string | The concrete coordinates placement resolved. |
| `lifecycle.phase` | string | Current phase (`active` / `suspended` / `decommissioning`). |
| `lifecycle.retentionUntil` | string | If a regime mandates a retention hold before destruction, the hold's expiry. |
| `lifecycle.exitAttestation` | string | Reference to the certified data-destruction / customer-exit evidence. |
| `conditions[]` | — | Standard XR conditions, plus `ResidencyAttested` (the chosen Zone — and any `dataServices` — provably satisfy `residency`). |

### Canonical Tenant claim

```yaml
apiVersion: platform.refplat.org/v1alpha2
kind: XTenant
metadata:
  name: payments-api-prod                       # logical identity = (team, name, environment)
spec:
  team: payments                                # → Team (envelope + SSO group)
  name: payments-api
  environment: prod                             # preprod | prod
  tier: pci                                      # → a platform hardening profile (∈ Team.allowedTiers)
  tenancy: { mode: dedicated, customer: bigbank }   # pooled (default) | dedicated(customer)
  residency: { allowedLocations: ["eu"] }       # HARD constraint, ⊆ Team.allowedLocations
  quota: { cpu: "8", memory: 16Gi, pods: 40 }   # validated ≤ Team.envelope.quotaCap
  domains:                                       # ADDITIONAL aliases only; <app>-<team>.<baseDomain> is implicit (ADR-061)
    - { host: bigbank.payments.example.com, canonical: true, dns: external }
  apps:
    api:
      repo: asanexample/payments-api             # owner/repo
      repoPath: k8s/prod
      preview: false
      serviceAccount: payments-api              # → a cloud-neutral identity is minted + bound
      permissions:
        aws:
          policyStatements:
            - sid: ReadCustomerBucket
              effect: Allow
              actions: ["s3:GetObject"]
              resources: ["arn:aws:s3:::asanexample-team-payments-*/*"]
  developerAccess: { enabled: true, group: payments-pci-oncall }   # override required for regulated prod
  encryption: { keyCustody: customer-managed }  # 🔒 reserved — dedicated CMK for BigBank (BYOK)
  lifecycle: { phase: active }                  # active | suspended | decommissioning (the exit path)
  dataServices:                                 # 🔒 reserved — inherits residency + tier recovery posture
    db:
      kind: relational
      engine: postgres
      class: prod
      serviceAccount: payments-api
      # backup omitted → tier `pci` default (≤1h RPO, 7y retention); an override may only strengthen it
# status.placement: { cloud, region, account, cluster, zone, namespace }
# status.lifecycle: { phase, retentionUntil, exitAttestation } + ResidencyAttested condition   (derived)
```

## Object 3 — Zone

A **platform-owned** account+cluster with an isolation policy — the unit of *hard* isolation and infra
provisioning. **Never authored by developers**; it exists so placement has concrete capacity to route into. A
Zone is keyed by `(environment, location, hardening, tenancy)`; placement matches a Tenant's intent to a Zone
with a compatible key.

Pooled zones are pre-provisioned by Terragrunt (a small stable cross-product of `tiers × locations-operated`).
Dedicated zones are vended per customer behind a [cloud-neutral interface](../adrs/049-tenant-model-team-tenant-zone.md#zones-pools-and-vending)
(mechanism deferred).

| Field | Required | Type | Purpose |
| ----- | -------- | ---- | ------- |
| `name` | yes | string | Stable Zone key, e.g. `prod-pci-eu` or `prod-dedicated-bigbank-eu`. |
| `environment` | yes | enum | `preprod` / `prod`. |
| `location` | yes | object | `cloud` + `region` (the concrete realization of a jurisdiction). |
| `hardening` | yes | enum | The tier profile this Zone realizes (`standard` / `elevated` / `regulated`). Maps the abstract tier to concrete isolation (see ADR-049 isolation spectrum). |
| `tenancy` | yes | enum | `pooled` / `dedicated`. |
| `customer` | iff dedicated | string | The `Customer` a dedicated Zone is the private home for. |
| `realized` | yes | object | `account` (AWS account ID) + `cluster` (the federated cluster name running its own Crossplane). |
| `encryption` | iff dedicated/regulated | object | 🔒 **Reserved.** Realizes the Customer / tier key-custody posture — the CMK/HSM the zone's resources encrypt under. |
| `capacity` | — | object | Optional pool sizing hints (advisory for placement). |

A Zone is where the abstract tier postures become concrete: it **realizes** the tier's recovery and
availability targets (backup config, AZ spread, DR replication) and — for a dedicated zone — the Customer's
`encryption.keyCustody`. Placement may only route a Tenant to a Zone whose realized postures **meet or exceed**
the Tenant's tier profile and `residency`.

```yaml
# platform-owned — Terragrunt-provisioned (pooled) or vended (dedicated). Not a developer artifact.
name: prod-pci-eu
environment: prod
location: { cloud: aws, region: eu-west-1 }
hardening: regulated                # one dedicated account+cluster per (env, regime): prod-pci
tenancy: pooled                     # regulated tenants share a compliance-boundary zone, namespace-isolated
realized: { account: "1234567890ab", cluster: prod-pci-euw1-eks }
```

A regulated Tenant defaults to **sharing** the `(env, regime)` compliance-boundary Zone (e.g. `prod-pci-eu`),
namespace-isolated within it — not one cluster per tenant. Escalation to a Tenant's own boundary
(`tenancy: dedicated`) is an explicit exception. The federated model (ADR-048) maps directly: a Zone *is* a
cluster running its own Crossplane + Composition; placement routes the claim to that cluster's control plane.

## Object 4 — Customer

A lightweight **placement attribute** — relevant only for `tenancy: dedicated`. It names who a dedicated Zone
is for and carries their compliance needs and contacts. Not an isolation primitive itself; it parameterizes
dedicated placement and vending.

| Field | Required | Type | Purpose |
| ----- | -------- | ---- | ------- |
| `name` | yes | string | Customer key, referenced by `Tenant.spec.tenancy.customer`. |
| `displayName` | — | string | Human label. |
| `complianceNeeds` | — | `[]enum` | Regimes the customer contractually requires (`pci` / `hipaa` / …) — informs which Zones may host them. |
| `residency` | — | `[]string` | Contractual jurisdiction(s) — constrains dedicated-Zone vending location. |
| `encryption` | — | object | 🔒 **Reserved.** `keyCustody` (`platform-managed` / `customer-managed` / `customer-hosted`) + optional `keyRef` — the BYOK/HYOK contract, realized by the customer's dedicated Zone. |
| `exit` | — | object | 🔒 **Reserved.** `retention` (contractual hold before destruction) + `dataDestruction` (`certified` / `standard`). Parameterizes the `decommissioning` lifecycle across all the customer's Tenants + dedicated-Zone teardown + key destruction. |
| `contacts` | — | `[]string` | Account/escalation contacts. |

```yaml
name: bigbank
displayName: BigBank PLC
complianceNeeds: [pci]
residency: ["eu"]
encryption: { keyCustody: customer-managed }     # 🔒 BYOK — dedicated CMK
exit: { retention: 7y, dataDestruction: certified }  # 🔒 contractual exit / right-to-erasure
contacts: ["platform-account-team@example.com"]
```

## Reserved dimensions (modeled now, realized post-rebuild)

These complete the model so the v2 API is enterprise-shaped from day one, but each is **inert until its
backing control ships**. They live in the schema now only because the rebuild bakes the API — reserving an
optional field is non-breaking; adding a dimension later is not.

| Dimension | Reserved as | Realized when | Why it has to be in the model now |
| --------- | ----------- | ------------- | --------------------------------- |
| **Data services** | `Tenant.spec.dataServices` | Data paved-road (#106/#107) | Without it, `residency` attests *compute* placement but not *data* placement — an incomplete residency guarantee. The field makes data inherit residency + recovery. |
| **Recovery / availability** | `tier` profile (derived) + `dataServices.<n>.backup` | Backup/DR system (ADR pending) | A `pci` tier *implies* RPO/RTO/retention; if the tier doesn't carry it, "what's our recovery posture?" has no answer in the model. |
| **Key custody (BYOK/HYOK)** | `Tenant.spec.encryption`, `Customer.encryption`, `Zone.encryption` | KMS/CMK paved-road | Customer-managed keys are a contractual gate for dedicated/regulated customers; bolting a key-custody axis on later reshapes Customer + Zone. |
| **Lifecycle / exit** | `Tenant.spec.lifecycle`, `Customer.exit` | Decommission workflow + evidence | Contractual customer isolation implies a contractual *exit* (certified destruction, retention holds, key destruction). Onboarding without offboarding is half a lifecycle. |
| **Consumption guarantees (QoS)** | *Not reserved — named omission* | Deferred | `quota` / `quotaCap` is a **cap, not a reservation**. Priority / preemption / guaranteed-capacity tiers are a real enterprise ask, **consciously deferred** — recorded here so it's an omission, not an oversight. |

## Identity from the model (ADR-053 generators)

The ADR-053 access-model-as-code compiles **one** source — these objects — into each system's native config.
The **Team** is the root of the taxonomy; the **Tenant** scopes it.

| Generated artifact | Read from | Result |
| ------------------ | --------- | ------ |
| Keycloak group + role + per-client claim mappers | `Team.ssoGroup`, `Team.name` | One group per Team; clean named OIDC group claim per client. |
| Identity Center account assignment | `Team.ssoGroup`, Tenant `placement.account` | `Dev-<team>` permission set assigned in the workload account. |
| ArgoCD policy (team-scoped Project) | `Team.name`, Tenant `team`/`apps` | `developer` role scoped to the Team's Project (no longer global `*/*`). |
| Kubernetes RoleBinding | `Team.developerGroup` (or Tenant override), `placement.namespace` | `team-<team>:developers` (or tenant-scoped) bound in the namespace. |
| Backstage permission policy (#197) | `Team.ssoGroup` | Group-based RBAC on OIDC group claims. |

### Developer access (posture)

`Tenant.spec.developerAccess` names only *who*; the **posture** is derived from `environment × tier` under
ADR-040 (kubectl is operate/debug, never authoring):

| Env × tier | Scope | Standing level | Elevation |
| ---------- | ----- | -------------- | --------- |
| preprod (any) | team-wide | operate | — |
| prod / standard | team-wide | view | operate via break-glass (time-boxed, audited) |
| prod / regulated | tenant-scoped (override group) | view | all elevation via break-glass + approval + audit; deployer ≠ approver |

## Envelope enforcement (the admission plane)

Generated RBAC is the user plane; Kyverno on the `Tenant` CR is the **envelope plane** — the authoritative,
bypass-proof guardrail (it fires however the claim arrived). It extends the existing S1
`restrict-tenant-control-plane` backstop with "…and only within your Team's envelope," reading the
projected `Team` CR:

- **Stateless, hard-enforced at admission:** `tier ∈ Team.allowedTiers`,
  `environment ∈ Team.allowedEnvironments`, `residency.allowedLocations ⊆ Team.allowedLocations`,
  per-tenant `quota ≤ Team.quotaCap`, `tenancy.customer` set iff `mode: dedicated`.
- **Stateful / aggregate, report-first:** sum of the Team's tenant quotas ≤ cap, dedicated zones in use ≤
  `maxDedicatedZones`. A small rollup controller writes `Team.status` and alerts; hard-enforce only if a Team
  actually pushes a cap.

## Migration from v1alpha1

The v1alpha1 `XTenant` ([crossplane-tenant-api.md](crossplane-tenant-api.md)) is the **interim** contract. v2
is breaking and lands with the rebuild — no in-place migration. Field-level delta:

| v1alpha1 | v1alpha2 | Change |
| -------- | -------- | ------ |
| `team` | `team` + `name` | Split: a Team now owns N Tenants. Namespace `team-<team>` → `<team>-<name>`. |
| `complianceTier` | `tier` | Renamed; `elevated` added; now validated against `Team.allowedTiers`. |
| — | `environment` | **New, required.** Tenants are realized per env (was implicit per-cluster claim). |
| — | `tenancy` | **New.** `pooled` (default) / `dedicated(customer)`. |
| — | `residency` | **New.** Hard, attested placement constraint. |
| `resourceQuota` | `quota` | Renamed; validated against `Team.quotaCap`. |
| `apps.<app>` (`repoPath`/`preview`) | `apps.<app>` (+ `repo`/`serviceAccount`/`permissions`) | **Per-app identity + permissions** absorbed — the single team-level `aws` block is gone. |
| `aws.serviceAccount` + `aws.policyStatements` | `apps.<app>.serviceAccount` + `apps.<app>.permissions.aws` | Moved per-app and cloud-keyed (was one role per team). |
| `developerAccess.enabled` | `developerAccess.enabled` + `group` | `group` override added (required for regulated prod). |
| `status.namespace` | `status.placement.{cloud,region,account,cluster,zone,namespace}` | Placement derives the full coordinate set, not just the namespace. |

The interim model (`team == tenant`, `teams.hcl` for delivery + supply-chain, the `tenant-claims` Terragrunt
unit) stands until the rebuild; this schema does not change it.
