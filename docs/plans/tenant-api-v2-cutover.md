# Step 4 — Tenant API v2 Cutover Plan

> **Status: SUPERSEDED — the platform went v1→v2→v3; v3 (ADR-067, XEnvironment) is live. See docs/plans/v3-implementation-plan.md. Retained for history.**
>
> **Status:** FINALIZED — ready to execute on go-ahead. The cutover is **breaking** and executes via the
> rebuild (`platctl teardown` → `bootstrap`); it is **gated on explicit go-ahead**. Steps 0–3 of the rebuild
> keystone are merged (PRs #287–#290); this is the final code (the "cutover commit") + the rebuild execution.
> Plan + resume checkpoint: `~/.claude/plans/structured-marinating-giraffe.md`. Background: ADR-049
> (Team/Tenant/Zone), the delivery plan's A6, `docs/architecture/tenant-api-v2.md`.
>
> **Locked decisions:** naming = env-suffix, team-first (`<team>-<name>-<env>`); stage ladder =
> `dev / test / uat / staging / prod`; the existing alpha/bravo `demo` tenants ship on **`dev`**; XRD drops
> `v1alpha1` on the fresh build; generated host stays `<app>-<team>` + `-<env>`. G1 (ECR ownership) and G3
> (stage-aware dev access) are **confirmed fast-follows** (latent until a team's 2nd stage), not cutover scope.

## What changes (v1 → v2)

| Dimension | v1 (today, live) | v2 (after cutover) |
|-----------|------------------|--------------------|
| XRD storage / referenceable | `v1alpha1` | `v1alpha2` |
| Composition | `tenant-v1` (`files/composition.yaml`) | `tenant-v2` (`files/composition-v2.yaml`) |
| Namespace | `team-<team>` (e.g. `team-alpha`) | **`<team>-<name>-<env>`** (e.g. `alpha-demo-dev`) |
| Claim shape | `spec.team` + `spec.aws.serviceAccount` | `spec.{team,name,environment,tier}` + per-app `apps.<app>.{serviceAccount,permissions}` |
| `metadata.name` | `<team>` (e.g. `alpha`) | **`<team>-<name>-<env>`** (e.g. `alpha-demo-dev`) |
| AWS identity | one `Pod-team-<team>` | per-app `Pod-<team>-<name>-<env>-<app>` |
| ECR repo | `team-<team>/<app>` | `team-<team>/<app>` (**unchanged** — team-scoped, env-agnostic image promoted across stages) |
| Generated route host | `<app>-<team>.<baseDomain>` (`demo-alpha…`) | **`<app>-<team>-<env>.<baseDomain>`** (`demo-alpha-dev…`) |
| Envelope Kyverno | `restrict-tenant-envelope` = **Audit** | **Enforce** |

### Environment-aware naming (DECIDED — "env-suffix, team-first")

The `environment` axis is **first-class** in the names (namespace, host, `metadata.name`), so multiple stages
(dev / test / uat / staging / prod) can co-locate in one cluster **or** later split across per-env clusters
without a rename — placement stays degenerate (everything lands on the one preprod cluster for now). One
`XTenant` claim per `(team, name, environment)` (ADR-049's identity). **Image is built once and promoted** —
the ECR repo `team-<team>/<app>` is env-agnostic; only the deployment target (namespace) and route host carry
the stage.

Consequence: the generated route host now carries `-<env>`, so app HTTPRoute hostnames **do change**
(`demo-alpha` → `demo-alpha-dev`). The app repos already need namespace PRs for the rebuild (A9), so the
hostname change folds in there. The ECR repo path stays stable.

**Stage ladder = `dev / test / uat / staging / prod`** (the global vocabulary). The cutover makes the model
*capable* of multi-stage; the alpha/bravo `demo` tenants ship as a single `dev` realization each
(`alpha-demo-dev`, `bravo-demo-dev`). Real multi-stage *use* by a team is gated on the G1/G3 fast-follows.

---

## A. The cutover commit (code changes)

One coordinated PR in this repo (plus the two cross-repo PRs in A9). Each item is offline-validatable; **none
is merged onto the running v1 cluster except as part of the rebuild** (see §C — teardown precedes the merge).

### A1 — XRD storage/referenceable flip + widen `environment` (`charts/tenant/templates/xrd.yaml`)

- `v1alpha2`: `referenceable: true`, `storage: true`.
- `v1alpha1`: **drop entirely** (fresh build — no stored v1alpha1 objects survive the teardown). Exactly one
  version may be `storage: true`.
- **Widen `spec.environment`** from `["preprod","prod"]` to `["dev","test","uat","staging","prod"]`. Widen the
  **Team CRD** `envelope.allowedEnvironments` enum (`charts/tenant/templates/team-crd.yaml`) to the same set,
  and set each team's actual permitted subset in `gitops/teams/*.yaml` (e.g. alpha/bravo →
  `["dev","test","uat","staging","prod"]`, or a narrower per-team subset). The enum is the universe; the
  per-team `allowedEnvironments` is the Kyverno-enforced ceiling; absence-of-claim is per-team opt-out.

### A2 — Deploy + bind Composition v2; retire v1

- Add `charts/tenant/templates/composition-v2.yaml` emitting `{{ .Files.Get "files/composition-v2.yaml" }}`
  (mirrors the existing `templates/composition.yaml`). **Composition v2 is currently not deployed at all** —
  only the v1 template exists.
- Composition v2's `compositeTypeRef` is already `v1alpha2`; once v1alpha2 is referenceable, claims bind to it.
- **Make the footprint env-aware** (the naming decision): `$ns = "%s-%s-%s" $team $name $env`
  (`alpha-demo-dev`); the per-app role becomes `Pod-<team>-<name>-<env>-<app>`; the generated route host
  becomes `<app>-<team>-<env>.<baseDomain>`. The ECR repo external-name stays `team-<team>/<app>` (env-agnostic).
- **Retire v1**: remove `templates/composition.yaml` + `files/composition.yaml` (fresh build → no v1 claims).
  Keeping both is harmless if only v1alpha2 is referenceable, but a clean removal avoids a dangling Composition.

### A3 — Port `restrict-images` into Composition v2 (the flagged gap)

- Composition v1 generates `restrict-images-team-<team>` (composition.yaml lines ~276–310); **Composition v2
  has only `restrict-route-hostnames`** (ported in Step 3). Port `restrict-images` too.
- **Porting subtlety (do not get this wrong):** in v1 the namespace `team-<team>` *coincided* with the ECR
  prefix, so the policy used `{{ $env.ecrRegistry }}/{{ $ns }}/`. In v2 `$ns = <team>-<name>-<env>`
  (`alpha-demo-dev`) but the **ECR prefix stays `team-<team>`**. The v2 policy must scope the allowed image to
  `{{ $cfg.ecrRegistry }}/team-{{ $team }}/*` (NOT `$ns`), while matching workloads **in** namespace `$ns`.
- **Name the policies per-namespace, not per-team** (Gap G2): `restrict-images-{{ $ns }}` and
  `restrict-route-hostnames-{{ $ns }}` (rename the Step-3 port too), each scoped to its `$ns`. Per-team names
  collide once a team has a second realization (stage or tenant).
- Update `render.sh`: alpha then renders **11** `kind: Object` (asserts `restrict-images-alpha-demo-dev` + the
  `…/team-alpha/` image prefix).

### A4 — Envelope Kyverno → Enforce (`crossplane` unit, preprod)

- In `infra/live/aws/preprod/us-east-1/platform/crossplane/terragrunt.hcl`, add to `tenant_policy_values`:
  `envelopeFailureAction = "Enforce"` (chart default is `Audit`; control-plane is already Enforce, `failurePolicy: Fail`).

### A5 — argocd-apps destination namespace → `<team>-<name>-<env>`

- In `infra/live/aws/platform/us-east-1/platform/argocd-apps/terragrunt.hcl`, set the per-tenant `namespace`
  in the `tenants` map: `namespace = "${team}-${claim.spec.name}-${claim.spec.environment}"`. The module's
  `tenant_namespaces` coalesce honors an explicit `namespace` over its `team-<team>` default — no module change
  required. (The generated host injected into the HTTPRoute likewise gains `-<env>`.)

### A6 — Rewrite the live claims to v1alpha2 (`gitops/tenant-claims/preprod/{alpha,bravo}.yaml`)

- Mirror the validated v1alpha2 fixtures: `apiVersion: platform.refplat.org/v1alpha2`;
  `metadata.name: alpha-demo-dev` / `bravo-demo-dev`; `spec.{team, name: demo, environment: dev,
  tier: standard}`; `apps.demo.{repo (owner/repo), repoPath, preview, serviceAccount}`;
  `developerAccess.enabled: true`. **Drop `spec.aws`** — `serviceAccount` moves onto the app entry; AWS perms
  (none today) would go under `apps.demo.permissions.aws.policyStatements`. One `dev` claim each — multi-stage
  is the new capability, not populated on day one.
- The `tenant-claims-preprod` ArgoCD app whitelists `XTenant` by group (version-agnostic) — no change needed.

### A7 — `createDeveloperClusterRole: true`

- The retired v1 `tenant` module owned the `tenant-developer` ClusterRole; the chart value is `false`
  (coexistence). On a fresh v2 build the tenant chart must create it (Composition v2's RoleBinding references
  it). Set `true` — verify the `crossplane` module/unit plumbs this chart value (small module change if not).

### A8 — Confirm the ArgoCD SA S1 exclusion (no change expected)

- `tenant_policy_values.extraExcludePrincipals` already lists `…assumed-role/ArgoCD/*` so ArgoCD can apply the
  cluster-scoped XTenant past `restrict-tenant-control-plane`. Just **verify** it carries through; no edit.

### A9 — Cross-repo ripples (separate, coordinated PRs)

- **`app-alpha`, `app-bravo`**: `k8s/preprod/` manifests' target namespace `team-<team>` →
  `<team>-demo-<env>` (`alpha-demo-dev` / `bravo-demo-dev`); the HTTPRoute hostname `demo-<team>` →
  `demo-<team>-<env>` (`demo-alpha-dev`); `catalog-info.yaml` `backstage.io/kubernetes-label-selector`.
- **`backstage`**: the platform-projection plugin is **v1-shaped** (hardcodes `team-<team>` namespace +
  `team-<team>/<app>` ECR; test is v1alpha1). Update it for v2 (namespace `<team>-<name>-<env>`, v1alpha2 schema) →
  **new Backstage image**, re-pushed after the `ecr`/`github-oidc` waves (the rebuild already requires a
  Backstage image re-push — runbook §1 gotcha #4).

---

## B. Pre-cutover validation

- **Offline (authoritative):** `.tenant-api-tests/run.sh` (schema) + `render.sh` (Composition v2 render incl.
  the new `restrict-images` assertion) green; the v1alpha2 live claims validate via `crossplane beta validate`.
- **Plan-clean where feasible:** `terragrunt hcl validate` on the changed units; the live `terragrunt plan`
  for the v2 changes is mostly exercised by the rebuild itself (the cluster is rebuilt, not updated in place).
- **Optional live smoke — RECOMMEND SKIP.** The plan floated applying a throwaway v1alpha2 claim + Composition
  v2 on the live preprod cluster before teardown. But making v1alpha2 referenceable **unbinds v1 from the real
  alpha/bravo claims** (only one version is referenceable), so a true on-cluster smoke is not additive and
  risks the live path. The AWS-provider paths (Pod-Identity, cross-account ECR) are exercised by the actual
  rebuild; rely on offline render + the §D rebuild verification instead.

---

## C. Execution — recommended sequencing (zero broken window)

The hazard: **v2 claims on a still-v1 cluster** — ArgoCD (`tenant-claims-preprod`, auto-sync) would apply
v1alpha2 against v1alpha1 storage, a lossy conversion that strips `spec.aws` and the `metadata.name` change
tears the tenant. Order **teardown before the cutover merge** to avoid the window entirely:

1. **Pre-flight** (runbook `docs/runbooks/platform-rebuild-from-scratch.md` §1): `./bin/platctl` built;
   `.platctl.yaml` present; manual prereqs in Secrets Manager; identity prereqs per the **de-Dex'd** runbook
   (Keycloak, not Dex SAML); `./scripts/bootstrap-iam-roles.sh` first (SCP); warm `aws sso login`; clear the
   tailnet split-DNS. Have the A9 cross-repo PRs + the rebuilt Backstage (v2-projection) image **ready**.
2. **Teardown on v1** — from current `main` (v1 code): `./bin/platctl teardown`. Cluster gone; **no stored
   v1alpha1 objects remain**, so the storage flip lands on an empty slate.
3. **Merge the cutover commit** (§A) → `main`. `main` is now v2.
4. **Bootstrap on v2** — `./bin/platctl bootstrap` (comes up with v1alpha2 storage, Composition v2,
   `<team>-<name>-<env>` namespaces, envelope Enforce). Re-push the v2-projection Backstage image after the
   `ecr`/`github-oidc` waves, then `--resume`.
5. **Apply the v2 claims** — ArgoCD `tenant-claims-preprod` syncs `gitops/tenant-claims/preprod/*` fresh
   (clean create, no conversion). The `teams` app (sync-wave −1) projects the Team CRs first.
6. **`./bin/platctl validate`**.

> **Simpler alternative (acceptable):** merge the cutover → `teardown` → `bootstrap` back-to-back. ArgoCD only
> briefly sees v2-on-v1 during teardown (it's torn down early and the cluster is going away). The teardown-first
> ordering above is the strictly-zero-window option.

---

## D. Verification (rebuild success criteria)

- `platctl bootstrap` reconstructs from code with **no manual steps beyond the documented prereqs / no orphaned
  state**.
- **XRD/Composition:** `v1alpha2` is storage+referenceable; Composition `tenant-v2` is bound; `tenant-v1` gone.
- **Tenants reconcile Ready:** `alpha-demo-dev`/`bravo-demo-dev` (v1alpha2) → namespaces
  `alpha-demo-dev`/`bravo-demo-dev`; per-app role `Pod-alpha-demo-dev-demo` + Pod-Identity for SA `app-alpha`;
  ECR `team-alpha/demo` (env-agnostic); the per-namespace **`restrict-images-alpha-demo-dev` and
  `restrict-route-hostnames-alpha-demo-dev`** ClusterPolicies present + Enforce.
- **Envelope Enforce works:** a claim that exceeds its Team envelope (tier ∉ `allowedTiers`, `environment` ∉
  `allowedEnvironments`, or quota > `quotaCap`) is **DENIED at admission**; a claim referencing a non-projected
  Team is denied (`team-must-exist`).
- **App delivery:** `app-alpha` deploys into `alpha-demo-dev`; HTTPRoute host
  `demo-alpha-dev.preprod.aws.refplat.org` admitted; cosign `verify-images`/`verify-attestations` still pass
  (supply chain unaffected — claim-derived since Step 2).
- **Backstage:** shows the v2 tenants with the correct namespace + ECR projection.

---

## E. Rollback posture

- **Before** the teardown + cutover merge, everything is additive — reverting restores v1.
- **After** teardown on v2 there is **no quick fallback**. Therefore **gate the teardown** on: all offline
  tests green; the v2 claim files reviewed; the A9 cross-repo PRs + the v2 Backstage image **ready to go**. The
  disaster path is `git revert` the cutover commit + re-bootstrap on v1 (a second full rebuild).

---

## F. Decisions (locked)

1. **Naming = env-suffix, team-first** — `<team>-<name>-<env>` namespace, `<app>-<team>-<env>` host,
   `metadata.name = <team>-<name>-<env>`. One `XTenant` per `(team, name, environment)`.
2. **Stage ladder = `dev / test / uat / staging / prod`** (XRD `environment` enum + Team CRD
   `allowedEnvironments` enum = this universe; per-team `allowedEnvironments` = the permitted subset).
   `preprod` is retired as a stage value (it's the *account/cluster*, a placement fact, not a stage).
3. **Existing alpha/bravo `demo` tenants ship on `dev`** — one `dev` claim each at cutover. Multi-stage is the
   new capability, gated on the G1/G3 fast-follows before any team actually adds a 2nd stage.
4. **Drop `v1alpha1` from the XRD** on the fresh build (no stored v1alpha1 objects survive the teardown).
5. **Generated route host = `<app>-<team>-<env>`** (env in the host label; co-located stages share the
   `*.<baseDomain>` wildcard). Per-env subdomains / per-env clusters stay deferred (placement).
6. **Live smoke — skip.** Making v1alpha2 referenceable unbinds v1 from the real claims, so an on-cluster
   smoke isn't additive; rely on offline render + the §D rebuild verification.

---

## G. Gaps surfaced by multi-stage (env-aware naming)

Making `environment` first-class means a team can have multiple **realizations** of the same tenant-app
(`alpha/demo` in dev + test + uat …). That breaks assumptions that held while there was one environment per
team. "Not all teams use all stages" itself needs **no new mechanism** — the ladder is the global vocabulary
(XRD enum + Team CRD `allowedEnvironments` enum); per-team *permission* is `Team.envelope.allowedEnvironments`
(Kyverno-enforced) and per-team *usage* is just which claims exist (no claim → no namespace). The real gaps:

- **G1 🔴 FAST-FOLLOW Shared team-scoped resources owned per-stage-claim (ECR).** The ECR repo
  `team-<team>/<app>` is env-agnostic (build once, promote), but Composition v2 creates it inside every claim's
  app loop → two stage claims become two owners of the same AWS repo, and `forceDelete` means tearing down one
  stage deletes the repo the others use. **Latent at cutover (demo = 1 `dev` stage); decoupling to a
  per-`(team,app)` owner is a confirmed fast-follow, GATED before any team runs a 2nd stage.** Same applies to
  any future env-agnostic, team-app-scoped resource.
- **G2 🟠 IN CUTOVER — Cluster-scoped policy-name collision** — fixed in A3 by per-namespace policy names.
- **G3 🟠 FAST-FOLLOW Developer access not stage-aware.** `developerAccess.enabled` defaults true per claim →
  devs get a RoleBinding in *every* stage namespace incl. prod. Extend the ADR-040 `environment × tier` posture
  to the ladder (prod/uat tighter or break-glass; dev loose). Confirmed fast-follow, GATED before a team's
  first non-`dev` stage. (No prod/uat claims exist at cutover, so latent.)
- **G4 🟡 Aggregate quota spans stages** — the Team `quotaCap` aggregate now sums N stage-namespaces; raises
  the priority of the (deferred) aggregate-quota controller. Per-claim quota already lets dev be small.
- **G5 🟡 Stage-aware ingress exposure** — dev/test want internal-only (Tailscale), prod public; today one
  shared Gateway. Defer (gateway work), but don't ship dev publicly reachable.
- **G6 🟡 Promotion gating** — "prod runs only an image that passed uat" is promotion machinery, deferred.

## Scope notes

- **In the cutover:** env-aware naming (A1/A2/A5/A6/A9), Composition v2 deploy+bind & v1 retire (A2), the
  `restrict-images` port + per-namespace policy names (A3, G2), envelope→Enforce (A4), `createDeveloperClusterRole`
  (A7), and the v1alpha2 live claims (A6, demo on `dev`).
- **Confirmed fast-follows (gated before any team's 2nd / non-`dev` stage, NOT cutover blockers):** **G1**
  (decouple env-agnostic team-app resources — ECR — to a per-`(team,app)` owner) and **G3** (stage-aware
  developer-access posture, ADR-040 extended to the ladder).
- **Still deferred (out of scope):** placement/Zones/Customer (A4/A5 of the delivery plan), the aggregate-quota
  controller (G4), stage-aware ingress exposure (G5), promotion gating (G6), reserved dimensions
  (encryption/dataServices/lifecycle), and BACK Phase 3 self-service — all built **on top of** this cutover.
