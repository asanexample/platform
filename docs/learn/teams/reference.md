# Learn: the Team — reference

A lookup reference for the `Team` CR. For the model behind these fields — the Team *is an envelope*,
the admission walk, SSO groups and roles — read the [domain model](../domain-model/orientation.md) and
[identity](../identity/orientation.md); this page is the schema and where each field bites.

## The object

`gitops/teams/<team>.yaml`, `kind: Team` (`platform.refplat.org/v1beta1`), `metadata.name: <team>`:

- **Cluster-scoped, data-only.** It's a plain CRD that provisions nothing — the admission-relevant
  mirror of a Team's identity and envelope. Not a Crossplane composite.
- **Dual-consumed.** The git file is read two ways: (1) projected to a read-only cluster `Team` CR by
  the ArgoCD `teams` app into `crossplane-system` (at `sync-wave: -1`, so Teams land before any
  Environment claim needs them); (2) read directly by Terragrunt units via `fileset` + `yamldecode`,
  keyed on `metadata.name`.
- **Required:** `spec` → `spec.ssoGroup` + `spec.envelope` → within the envelope,
  `allowedTiers` + `allowedStages` + `quotaCap`.

## `spec.envelope` — the bound on every Product/Environment the Team may author

| field | required | type / enum | bounds |
| --- | --- | --- | --- |
| `allowedTiers` | ✅ | array, `standard`\|`elevated`\|`pci`\|`hipaa` | compliance tier an Environment may request |
| `allowedStages` | ✅ | array, `dev`\|`test`\|`uat`\|`staging`\|`prod` | stage an Environment may deploy to |
| `allowedLocations` | | array of string, default `["*"]` | data-residency regions an Environment may pick |
| `quotaCap` | ✅ | `cpu` (str), `memory` (str), `pods` (int) | per-Environment `ResourceQuota` ceiling (absent dim = effectively unlimited) |
| `budget.monthlyUSD` | | number ≥ 0 | cost guardrail — surfaced/alerted only, **not read by the Composition**; absent = surfaced-but-unbounded |
| `maxDedicatedIsolation` | | `cluster` (int≥0), `account` (int≥0), default `{cluster:0, account:0}` | how many Environments may dial the expensive isolation rungs; `0` = pooled only |
| `maxCrossTeamGrantsPerProduct` | | int, default `10`, min 0 | cap on active inbound AccessGrants per Product |
| `resources.allowedEngines` | | array, `s3`\|`sqs`\|`sns`\|`dynamodb`, default `[]` | self-service cloud engines the Team may declare; empty = none (**default-deny**) |
| `resources.maxPerEnvironment` | | int, default `0`, min 0 | max self-service resources per Environment |
| `resources.isolationFloor` | | `shared`\|`dedicated`, default `shared` | lowest data-isolation rung requestable |

## Identity, routing, and status (not envelope)

| field | type | meaning |
| --- | --- | --- |
| `spec.ssoGroup` | string, ✅ | upstream IdP/Keycloak group the Team maps to (e.g. `Dev-alpha`) — root of both authz planes |
| `spec.slack.channel` | string | incident channel the owner-routing agent posts to |
| `spec.pagerduty.escalationPolicyId` | string | live on-call pointer |
| `spec.oncall.{primary,fallback}` | arrays of GitHub logins | static accountable-contact fallback |
| `spec.platformTrust` | `clusterRoles[]`, `allowedIamActions[]`, default `{}` | **platform-owned Teams only** — cluster-read roles + IAM actions past the deny-set that tenants can't request |
| `status.productCount` / `environmentCount` / `dedicatedIsolationInUse` | int / int / obj `{cluster, account}` | controller-written rollup. The `kubectl get teams` printer columns are **SSO Group** (`.spec.ssoGroup`), **Stages** (`.spec.envelope.allowedStages`), and **Environments** (`.status.environmentCount`) |

## Where each field is enforced

The envelope is checked at **three layers, all reading the same fields**:

| layer | what | reads |
| --- | --- | --- |
| **Kyverno admission** (`restrict-environment-envelope`) — the real gate | `deny`s an `XEnvironment` claim outside the envelope: tier/stage in the allowed set, quota ≤ `quotaCap`, residency ⊆ `allowedLocations`, engine ∈ `allowedEngines`, resource count ≤ `maxPerEnvironment`, IAM deny-set | projected `Team` + `Product` CRs |
| **gitops gate** (`validate-environments.sh`, shift-left) | the *same* checks pre-merge, from the trusted `main` base checkout | `gitops/teams/<team>.yaml` |
| **Composition** (`environment-api`) | materializes the claim's own `spec.quota` into a `ResourceQuota` — it renders what admission already bounded, it does **not** re-read `quotaCap` | the `XEnvironment` claim |

The CRD itself does **not** bound `quotaCap` / `maxDedicatedIsolation` / `ssoGroup`, so the **Teams
gate** (`teams-gate.yml`, required check "Teams Approval") adds platform ceilings (`MAX_QUOTA_CPU=64`,
`MAX_QUOTA_MEMORY=256Gi`, `MAX_QUOTA_PODS=500`, `MAX_DEDICATED_ISOLATION=0`, `MAX_RESOURCES_PER_ENV=25`),
a denied-group check (`DENIED_SSO_GROUPS=platform-admins`), enum/required-field validation, and a
**deletion guard** (a Team can't be removed while an Environment still references it). Teams stay
human-reviewed — no auto-merge arm.

## Derivations — per-Team vs per-Product

A Team materializes **identity, ownership, and the governance envelope**. Everything with a
`<team>-<product>` name is derived from the **Product** registry, not the Team — the `<team>` there is a
coordinate, not a per-Team fan-out.

| scope | artifact | unit | keyed on |
| --- | --- | --- | --- |
| **per-Team** | GitHub org team (human ownership grant) | `github-teams` | `metadata.name` |
| **per-Team** | one Keycloak group (the Team's SSO identity) | `keycloak-config` | `metadata.name` → `spec.ssoGroup` |
| **per-Team** | Backstage `Group` (catalog projection) | `backstage` | projected `Team` CR |
| **per-Team** | incident routing | owner-routing agent | `spec.slack.channel` |
| per-**Product** | CI ECR-push role, `verify-images`/`verify-attestations` policies, ApplicationSet, per-Service Pod-Identity + ECR repos | `github-oidc` / `policy` / `argocd-apps` / Composition | `spec.repo` / `<team>-<product>` (from the **Product** registry) |

> Org-team membership is **not** in the Actions OIDC token, so it never carries the cosign/Kyverno
> supply-chain identity — that anchors on repo name + per-Product role.

## Drift flags (designed-not-built / stale)

- **The scaffolder skeleton is stale vs the live schema.** `scaffolder/templates/new-team/skeleton/…`
  still emits `apiVersion: …/v1alpha2`, `envelope.allowedEnvironments`, and `maxDedicatedZones: 0`.
  Live CRs use `v1beta1`, `allowedStages`, and `maxDedicatedIsolation` — and never emit `slack`,
  `budget`, or `resources`. Copy an existing `gitops/teams/<team>.yaml` rather than trusting the skeleton.
- **`keycloak-config` reads the old field name.** The module derives developer-access roles from
  `try(cfg.envelope.allowedEnvironments, [])`, but live CRs name it `allowedStages` — so the fallback
  silently yields `[]`: a Team gets its Keycloak *group* but no stage-derived developer-access roles.
- **Per-team kubectl isn't built.** The group→role mapping exists in Keycloak, but the
  `DeveloperAccess-<team>` IAM role + EKS access entry is deferred; the Composition emits only the
  in-cluster `developers` RoleBinding. Use `platctl kubeconfig` / PlatformAdmin until built.
- **`platformTrust` is unset on every real Team.** Platform agents get cluster-read + Bedrock from
  the `XAgent` Composition on the hub, not by a tenant Environment requesting a Team's `platformTrust`.
- **Approver holding lives in `gitops/people`, not on the Team.** `spec.roles` is not a valid Team key.

## Go deeper

- The model: [domain model](../domain-model/orientation.md) · [identity](../identity/orientation.md).
- The consumers: [Environment API](../environment-api/orientation.md) · [Policy](../policy/orientation.md) ·
  [Self-service resources](../self-service-resources/orientation.md).
