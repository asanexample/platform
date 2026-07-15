# Kyverno Policy Catalog

The authoritative list of Kyverno admission policies enforced on each cluster, what they check, and
how they are scoped. Policies are defined once in the shared `policy` module
(`infra/modules/policy/policies-chart/`) and parameterised per cluster by the live Terragrunt units
(`infra/live/aws/<env>/us-east-1/platform/policy/`). See [ADR-014](../adrs/014-kyverno-as-policy-engine.md)
for the decision and rollout, and the [break-glass runbook](../runbooks/kyverno-break-glass.md) for
emergency disable / the Audit↔Enforce flip.

> **Source of truth:** the policies are generated from the module — this page is a human-readable
> mirror. To see the live state on a cluster: `kubectl get clusterpolicy` (READY/ADMISSION/BACKGROUND
> columns) and `kubectl get cpol <name> -o yaml`.

## Per-cluster deployment status

| Cluster | Account | Engine | Mode | Admission replicas | Compliance tier | Policy count |
| ------- | ------- | ------ | ---- | ------------------ | --------------- | ------------ |
| **preprod** | 620830101009 | v1.18.1 | **Enforce** | 1 | standard | 14 |
| **platform** | 829808296602 | v1.18.1 | **Enforce** | 3 (HA) | standard | 12 |
| **prod** | 554518885123 | _not deployed_ | — | — | _TBD_ | — |

- The **count differs** because several policy _families_ are generated one-per-product. The platform-owned
  `verify-images-product-<team>-<product>` and `verify-attestations-product-<team>-<product>` render from the
  **Product registry** (`gitops/products/`) in the `policy` unit; the per-environment `restrict-images-<team>-<product>-<stage>` and
  `restrict-route-hostnames-<team>-<product>-<stage>` are owned by the Crossplane Environment Composition (one per environment namespace).
  The registry currently holds **six** products (`alpha-shop`, `alpha-checkout`, `bravo-dispatch`,
  `platform-flagship`, `platform-pulse`, `platform-triage-copilot`), and preprod reads `gitops/products/`
  unfiltered, so each verify-* family contributes one policy per product. (`alpha-checkout` is registered
  as a Product but currently has no live Environment claim, so it renders a `verify-*` pair but no
  `restrict-images-*`/`restrict-route-hostnames-*` — those are per-environment, not per-product.)
  The **platform cluster is not "common policies only"**: it runs a
  platform-owned workload — the `triage-copilot` XAgent on the hub (ADR-082) — and enables image **and**
  attestation verification in **Enforce**, so it too renders `verify-images-product-*` /
  `verify-attestations-product-*` (for the agent's product). It carries no per-_environment_ policies
  (`restrict-images-*`/`restrict-route-hostnames-*`) because it hosts no tenant environment namespaces. The
  counts above are an indicative snapshot — read the exact live total with `kubectl get cpol` (it shifts as
  environments/phases change).
- **Mode** is controlled by the unit's `validation_failure_action` (`Audit` records PolicyReports and
  fails the webhook open; `Enforce` rejects at admission and fails the webhook closed). The flip is a
  one-line input change + apply.

## Policies

**Scope** column:

- _environment_ — matches only namespaces carrying the `platform.refplat.org/team` label (infra
  namespaces excluded). Inert on clusters with no environment namespaces (e.g. platform).
- _cluster_ — evaluates cluster-wide at admission; skips the principals in `exclude_principals`
  (the IaC deployer, ArgoCD, and Kubernetes system controllers). These run `background: false`
  (Kyverno disallows `userInfo` in background scanning), so they only act on new `CREATE`/`UPDATE`.

| Policy | Target kind(s) | Enforces | Scope | Tier | Clusters |
| ------ | -------------- | -------- | ----- | ---- | -------- |
| `restrict-image-registries` | Pod | Images only from approved registries (the platform ECR) | environment | all | preprod, platform |
| `restrict-images-<team>-<product>-<stage>` | Pod | A product's environment namespace may only run `…/team-<team>/<product>-*` images (one per environment namespace, owned by the Environment Composition) | environment (per-namespace) | all | preprod (one per live env — currently 12: alpha-shop's 5 stages, bravo-dispatch's 5 stages, `platform-flagship/dev`, `platform-pulse/dev`; exact live set is `gitops/environments/`, not this table) |
| `disallow-latest-tag` | Pod | Explicit, non-`latest` image tag required | environment | all | preprod, platform |
| `require-requests-limits` | Pod | CPU + memory requests **and** limits on every container | environment | all | preprod, platform |
| `require-pod-probes` | Pod | Liveness + readiness probes on every container | environment | all | preprod, platform |
| `require-prod-replica-floor` | Deployment, StatefulSet (+ Rollout when enabled) | In `*-prod` namespaces, `replicas >= 2` (or HPA `minReplicas >= 2`) — a single replica can't be zero-downtime (ADR-085); replicas validated, never mutated | environment | all | preprod, platform (**Enforce** both, #844) |
| `restrict-automount-sa-token` | Pod | `automountServiceAccountToken: false` | environment | all | preprod, platform |
| `require-workload-labels` | Pod | `app.kubernetes.io/name` + `team` labels | environment | all | preprod, platform |
| `block-public-loadbalancer` | Service | Deny `LoadBalancer` / `NodePort` (Gateway-only ingress) | environment | all | preprod, platform |
| `disallow-irsa-annotation-cross-team` | ServiceAccount | Deny `eks.amazonaws.com/role-arn` annotation (environment AWS access is Pod Identity, not IRSA — ADR-041; backstop) | environment | all | preprod, platform |
| `require-environment-namespace-naming` | Namespace | Environment namespaces named `<team>-<product>-<stage>` | environment (labelled ns) | all | preprod, platform |
| `restrict-binding-clusteradmin` | RoleBinding, ClusterRoleBinding | Deny binding to `cluster-admin` | cluster | all | preprod, platform |
| `restrict-wildcard-rbac` | Role, ClusterRole | Deny wildcard verbs / resources / apiGroups | cluster | all | preprod, platform |
| `disallow-default-namespace` | Pod, Deployment, StatefulSet, DaemonSet, ReplicaSet, Job, CronJob | No workloads in `default` | cluster | all | preprod, platform |
| `disallow-privilege-escalation` | Pod | Deny `securityContext.allowPrivilegeEscalation: true` (backstops the mutate default) | environment | all | preprod, platform |
| `require-seccomp` | Pod | Deny `seccompProfile.type: Unconfined` (backstops the mutate default) | environment | all | preprod, platform |
| `restrict-route-hostnames-<team>-<product>-<stage>` | HTTPRoute, GRPCRoute, TLSRoute | Per-environment route hostnames must be in the product's allow-list (from `spec.domains`, owned by the Environment Composition, one per environment namespace); deny cross-product/platform hostnames + empty hostname lists (anti-squatting, ADR-029) | environment (per-namespace) | all | preprod (one per live env — currently 12: alpha-shop's 5 stages, bravo-dispatch's 5 stages, `platform-flagship/dev`, `platform-pulse/dev`; exact live set is `gitops/environments/`, not this table) |
| `require-pod-security-restricted` | Pod | Full Restricted Pod Security Standard | environment | **hipaa/pci only** | _(none yet — standard tier)_ |
| `require-ro-rootfs` | Pod | `readOnlyRootFilesystem: true` | environment | **hipaa/pci only** | _(none yet — standard tier)_ |

The two tier-gated policies render only when a cluster's `compliance_tier` is `hipaa` or `pci`. Both
current clusters are `standard`, so they are not deployed there yet; they will appear automatically on
any cluster set to a regulated tier (e.g. a future prod). See [ADR-013](../adrs/013-compliance-tier-model.md).

## Mutate policies (Phase 2)

`mutate` policies auto-inject safe defaults on environment workloads at admission (add-if-absent — never
overrides an explicit app value), so apps need no security boilerplate and still satisfy the validate
policies (Kyverno mutates before validating). Gated by `enable_mutate_defaults` (default true); the
mutate webhooks **fail open** (a missed default must never block a pod). Their security values are
_enforced_ by the `disallow-privilege-escalation` / `require-seccomp` validate backstops above, so the
matching ArgoCD `ignoreDifferences` is safe.

| Policy | Injects (when absent) | Scope |
| ------ | --------------------- | ----- |
| `mutate-pod-defaults` | container `securityContext` (`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`; not `runAsNonRoot`), pod `automountServiceAccountToken: false`, **and the graceful-drain defaults (ADR-085): container `lifecycle.preStop` sleep + pod `terminationGracePeriodSeconds: 30`** — one patch so strategic-merge resolves under autogen | environment |
| `mutate-automount` | pod `automountServiceAccountToken: false` when unset (least-privilege default; satisfies `restrict-automount-sa-token`) | environment |
| `mutate-workload-labels` | `team` (derived from the `<team>-<product>-<stage>` namespace name) | environment |
| `mutate-topology-spread` (ADR-085) | `topologySpreadConstraints` (zone + node, soft) on environment Deployments/StatefulSets when absent, selector derived from the workload | environment |

> `app.kubernetes.io/name` can't be auto-derived under autogen (pod templates have no name), so it is
> **recommended but not required** — `require-workload-labels` requires only `team`, which is
> auto-injected. Apps therefore need no label boilerplate.

ArgoCD is told to ignore the mutated sub-fields (`argocd_cm_extra` in the `argocd` unit) so selfHeal
doesn't fight Kyverno — split across two keys, not one: the scalar/map-key paths
(`automountServiceAccountToken`, the `labels.*` rules) sit in the kind-unscoped
`resource.customizations.ignoreDifferences.all`, while the array-notation `securityContext.*` paths
(`containers[]?...`, `initContainers[]?...`) are scoped to `.apps_Deployment`/`.apps_StatefulSet` only —
deliberately excluding `argoproj.io/Rollout`. Rollout is a CRD without a registered Kubernetes scheme, and
an array-notation `ignoreDifferences` rule on such a CRD makes ArgoCD's sync fall back to a JSON Merge
Patch that replaces arrays wholesale instead of merging them — silently reverting a Rollout's
`containers[].image` to the stale live value while still reporting a successful sync. See
[debug-argocd-sync.md](../runbooks/debug-argocd-sync.md#synced-but-stale-rollout-image-silently-dropped).

## Generate policies (ADR-085 availability)

`generate` policies create and keep-in-sync a companion resource.

| Policy | Generates | Scope | Gate |
| ------ | --------- | ----- | ---- |
| `generate-workload-pdb` | A `PodDisruptionBudget` (`<workload>-pdb`, `maxUnavailable: 1`, selector derived from the workload) for every environment Deployment/StatefulSet (+ Rollout when `enableRolloutKind`) — created, kept in sync, and GC'd with the workload; drain-safe, only meaningful at `>= 2` replicas (ADR-085) | environment | `enable_pdb_generate` |
| `sync-platform-db-secret` | Clones a CNPG `<cluster>-app` credential Secret from a platform-database namespace into a stateful platform Product's Environment namespace (secretKeyRef can't cross namespaces), `synchronize` + `generateExisting` (ADR-099 Flagship; ADR-081). RBAC splits cluster-wide READ (forced by the generateExisting cluster-scoped list) from namespace-scoped WRITE. Namespace pairs declared per binding at the unit | per-binding namespace pair | `enable_db_secret_sync` |

Together with the `mutate-topology-spread` / graceful-drain mutations and the `require-prod-replica-floor`
validate above, this is the ADR-085 zero-downtime suite — applied live on both clusters.

## Image verification (Phase 3 — cosign keyless)

Gated by `enable_image_verification`; rolls Audit→Enforce via its **own** `verify_failure_action`
(independent of the validate/Enforce action above). Image signing now runs in the shared, app-team-
unwritable **`asanexample/trusted-ci/.github/workflows/build-sign.yml`** reusable workflow (cosign
keyless, GitHub Actions OIDC → Fulcio/Rekor; ADR-050) — app `deploy.yml`/`preview.yml` are thin callers.
Kyverno fetches the signature from ECR (via an **EKS Pod Identity** association granting ECR read — ADR-047, no SA annotation) and admits images signed by
that shared workflow when the cert's `githubWorkflowRepository` extension is the product's own
`<team>-<product>` caller repo. Two policy inputs drive this: the cluster-wide
`trusted_ci_build_subject_regexp` (the shared signer subject) and the per-product `verify_subjects_product`
map — derived from the **Product registry** (`gitops/products/<team>/<product>.yaml`, `spec.repo`), whose
`repo` field is the caller-repo gate. A product's own app-signed identity (`verify_subjects_product`'s
optional `appSubjects`) remains a supported fallback for bespoke-build apps.

| Policy | Verifies | Scope |
| ------ | -------- | ----- |
| `verify-images-product-<team>-<product>` | Images under `…/team-<team>/<product>-*` are cosign-signed (`count: 1`) by the shared `trusted-ci/build-sign.yml` (`trusted_ci_build_subject_regexp`) gated per-product by the `githubWorkflowRepository` extension = `<team>-<product>` (`verify_subjects_product[*].repo`, ADR-050) **or**, as a fallback, by `<team>-<product>`'s own `deploy.yml@main` (pinned) / `preview.yml` (subjectRegExp — the PR OIDC ref varies); `mutateDigest` pins to digest | environment (per-product) |

Per-product identity isolation: the shared signer's cert **subject** is the same for all products, so isolation
moves to the `githubWorkflowRepository` cert extension — Fulcio sets it from the _calling_ app repo's OIDC,
so one product cannot forge another's. A signature whose caller repo (or, for the fallback, whose app
workflow) is not the product's does **not** satisfy that product's policy — the supply-chain analog of
per-product registry scoping. Deployed in **Enforce on both preprod** (tenant environments) **and platform**
(the `triage-copilot` XAgent on the hub, ADR-082) — the platform cluster does run a platform-owned, signed +
attested workload, so it renders these per-product policies too. Verification depends on cluster egress to
sigstore (Fulcio/Rekor) — see the break-glass runbook.

## Attestation verification (Phase 3 — SBOM + SLSA provenance)

Gated by `enable_attestation_verification` (requires `enable_image_verification`), with its **own**
`verify_attestations_failure_action` so the SBOM/provenance requirement can roll out Audit-first while
signature verification stays Enforce. On top of the image _signature_, this requires the image to carry
two cosign-signed **attestations**: a CycloneDX **SBOM** (`https://cyclonedx.org/bom`) and a **SLSA
provenance** (`https://slsa.dev/provenance/v0.2`). **Enforce on preprod** as of 2026-05-30, and **Enforce on
platform** for the hub `triage-copilot` agent (ADR-082). The SBOM is now signed by the shared
`trusted-ci/build-sign.yml` workflow alongside the image signature (ADR-050).

| Policy | Verifies | Scope |
| ------ | -------- | ----- |
| `verify-attestations-product-<team>-<product>` | `…/team-<team>/<product>-*` images carry a cosign-signed CycloneDX SBOM **and** a SLSA provenance attestation. The SBOM block accepts (`count: 1`) the shared `trusted-ci/build-sign.yml` (`trusted_ci_build_subject_regexp`) gated per-product by `githubWorkflowRepository` = `<team>-<product>` (`verify_subjects_product[*].repo`, ADR-050) **or**, as a fallback, the product's own workflow. For SLSA-L3-adopted products, the provenance must be signed by the isolated **`trusted-ci`** reusable workflow with the caller-repo = the product's own `<team>-<product>` (ADR-042); for others, by the product's own `deploy.yml`/`preview.yml`. Break-glass: `attest_failure_action`. | environment (per-product) |

This is the admission-side counterpart to the image-signing/attestation chain in
[`cosign-image-signing.md`](cosign-image-signing.md) §10b — the signature proves _who built_ the image;
these attestations prove the SBOM and _how_ it was built.

## Cleanup (Phase 5)

`ClusterCleanupPolicy` `cleanup-finished-cronjob-jobs` (gated by `enable_cleanup`) reaps **finished
CronJob-spawned Jobs** in environment namespaces on an hourly schedule. Scoped to CronJob-owned Jobs so it
never deletes a Git-declared/ArgoCD-managed Job (selfHeal would recreate it). CleanupPolicies have no
Audit mode — they delete on schedule.

## Exemptions (so the platform never blocks itself)

Configured on the module and applied to every cluster:

- **`exclude_namespaces`** (environment policies skip these): `kube-system`, `kube-node-lease`,
  `kube-public`, `kyverno`, `cert-manager`, `external-secrets`, `external-dns`, `argocd`, `tailscale`.
- **`exclude_principals`** (cluster-scoped policies skip these usernames): the IaC deployer
  `arn:aws:sts::*:assumed-role/PlatformDeployer/*`, ArgoCD `system:serviceaccount:argocd:*`,
  `system:serviceaccount:kube-system:*`, `system:nodes:*`, `system:kube-controller-manager`.
  **PlatformAdmin is intentionally not exempt** — it is read+operate, not author (ADR-040).

## Adding a cluster (e.g. prod)

1. Add a `policy/terragrunt.hcl` unit under the env mirroring the existing ones (eks + node-groups
   deps, helm provider, `allowed_registries` from the platform ECR, `verify_subjects_product` derived from the
   Product registry (`gitops/products/`) if any, `compliance_tier` from `workload.hcl`).
2. Apply in **Audit**; confirm PolicyReports are clean against real workloads
   (`kubectl get policyreport -A`).
3. Flip `validation_failure_action` to **Enforce** and apply. For shared-services clusters, validate
   the cluster-scoped RBAC policies against the platform controllers first (the `exclude_principals`
   list must cover every principal that legitimately creates cluster RBAC).
4. Update the status table above.

## Related

- [ADR-014: Kyverno as Policy Engine](../adrs/014-kyverno-as-policy-engine.md) — decision, rollout, phase roadmap
- [ADR-013: Compliance Tier Model](../adrs/013-compliance-tier-model.md) — tier → policy mapping
- [Kyverno break-glass runbook](../runbooks/kyverno-break-glass.md)
- Module: `infra/modules/policy/` (`README.md`, `policies-chart/templates/`)
