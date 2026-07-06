# Learn: Policy & Admission — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first.

## The engine

- **[Kyverno](https://kyverno.io/docs/) v1.18.1**, HA, on the cluster's **admission** webhook — evaluates
  every resource create/update. Layered **above** the native **Pod Security Admission `baseline`** floor
  (ADR-014): PSA is the backstop, Kyverno expresses what PSA can't (registry scoping, hostname allow-lists,
  per-product rules).
- The `policy` module holds **no team data**. Per-product values are derived from the **`Product` registry**
  (`fileset` + `yamldecode`) at apply time.

## The three verbs

| Verb | What it does | Example policies |
| --- | --- | --- |
| **validate** | reject a non-compliant resource at admission | `disallow-latest-tag`, `require-requests-limits`, `require-pod-probes`, `restrict-image-registries`, `restrict-images-<env>`, `require-prod-replica-floor` |
| **mutate** | rewrite the resource on the way in (inject safe defaults) | `mutate-pod-defaults` (drop caps, `allowPrivilegeEscalation:false`, `seccomp:RuntimeDefault`, automount off), `mutate-workload-labels` (`team`), `mutate-topology-spread` |
| **generate** | create a companion resource alongside it | `generate-workload-pdb` (a `maxUnavailable:1` PDB per workload, ADR-085) |

## The policy catalog (shape)

- **Baseline (platform-wide, Phase 1):** latest-tag, requests/limits, probes, seccomp, privilege-escalation,
  registry allow-list, default-namespace, wildcard-RBAC, cluster-admin binding, workload naming/labels.
- **Mutate (Phase 2):** securityContext + automount defaults, `team` label, topology spread.
- **Generate (ADR-085):** the per-workload PodDisruptionBudget.
- **Per-product (derived, per environment namespace):** `restrict-images-<team>-<product>-<stage>` (only
  `…/team-<team>/<product>-*` images) and `restrict-route-hostnames-<…>` (only the Environment's hostnames).
  **Owned by the [Environment Composition](../environment-api/orientation.md)** (ADR-046) — rendered with the
  namespace.
- **Supply chain (Phase 3, cosign keyless, Enforce):** `verify-images-product-<product>` (signed) +
  `verify-attestations-product-<product>` (SBOM + SLSA provenance). Platform-owned, per product.
- **Governance:** `restrict-environment-control-plane` (only the ArgoCD role may create `XEnvironment`s),
  `restrict-environment-envelope`, `restrict-over-budget-provisioning`.

Full per-cluster catalog + status: [`kyverno-policy-catalog.md`](../../architecture/kyverno-policy-catalog.md).

## Audit-first → Enforce

- **Audit:** violations recorded as **`PolicyReport`s**; resource **admitted**; webhook fail-**open**
  (`failurePolicy: Ignore`). Observe what would break.
- **Enforce:** violations **rejected**; webhook fail-**closed** (`Fail`) — the `validate.kyverno.svc-fail`
  you see in a rejection. The flip is a deliberate, per-policy step.

## Gotchas that teach

- **⚠️ Enforce/Audit lives in the *rule*, not the spec.** In v1.18 it's each rule's `validate.failureAction`.
  The top-level `spec.validationFailureAction` is **deprecated** and defaults to `Audit` — so
  `kubectl get clusterpolicy -o …spec.validationFailureAction` **lies** (shows `Audit` even where rules
  Enforce). Read the per-rule field, or just test admission. (This asymmetry is a latent fail-open risk on a
  security control — [#1184](https://github.com/asanexample/platform/issues/1184) tracks a guard.)
- **A per-policy `matchConditions` doesn't skip the *aggregated* webhook.** Kyverno serves all policies
  through one aggregated webhook; to make it ignore a resource you need a **global engine** matchCondition,
  not a per-policy one (#830).
- **A `generate` rule's match is immutable.** You can't change an existing generate rule's match in place —
  add a *new* rule (burned ADR-056 #856).
- **Availability policies don't match `Rollout` by default.** `require-prod-replica-floor`,
  `generate-workload-pdb`, `mutate-topology-spread` only match `argoproj.io/v1alpha1/Rollout` when
  **`enable_rollout_kind = true`** (default off — a Kyverno rule can't name an absent CRD, #7839). Pod-level
  policies cover Rollout pods automatically via ReplicaSet autogen. (See the
  [Delivery reference](../delivery/reference.md).)
- **The platform exempts itself.** System namespaces (kube-system, kyverno, argocd, karpenter, …) are
  excluded so admission can never block the platform's own components.

## Glossary

- **Admission** — the API-server checkpoint every resource crosses before storage; where Kyverno runs.
- **`ClusterPolicy`** — a cluster-scoped Kyverno policy (validate / mutate / generate rules).
- **`PolicyReport`** — Kyverno's per-resource pass/fail record (how Audit surfaces violations).
- **failureAction** — per-rule `Enforce` (reject) vs `Audit` (record only).
- **PSA (Pod Security Admission)** — Kubernetes' native pod-security tiers; the `baseline` floor under Kyverno.
- **autogen** — Kyverno auto-deriving pod rules for controllers (Deployment→ReplicaSet→Pod), so a
  pod policy covers workloads without you writing the controller variants.

## Go deeper

- [Kyverno policy catalog](../../architecture/kyverno-policy-catalog.md) (as-built, per-cluster) ·
  [ADR-014](../../adrs/014-kyverno-as-policy-engine.md).
- Author policies: the `kyverno-policy-authoring` skill. Write compliant workloads:
  `authoring-k8s-workloads` + [`compliant-deployment.yaml`](../../examples/compliant-deployment.yaml).
- Substrate: [Kyverno](https://kyverno.io/docs/) ·
  [admission control](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) ·
  [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/).
