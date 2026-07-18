# Policy (Kyverno)

Deploys the [Kyverno](https://kyverno.io/) policy engine and the platform's admission-control
ClusterPolicies on a Kubernetes cluster (ADR-014). Kyverno layers above the Pod Security Admission
`baseline` floor (ADR-027/040) to express controls PSA cannot: per-environment image-registry scoping,
cross-team IRSA-annotation prevention, RBAC hardening, resource/label requirements, and tier-gated
restricted Pod Security.

The module is **cloud-agnostic and holds no team-specific data** — per-product values
(`allowed_registries`, `verify_subjects_product`) are supplied by the Terragrunt unit, derived from the
**Product registry** (`gitops/products/`).

## Design

- **Two Helm releases.** `helm_release.kyverno` installs the engine (HA admission controller);
  `helm_release.policies` installs a bundled local chart (`policies-chart/`) of our ClusterPolicies
  and `depends_on` the engine. A local chart needs no plan-time access to the Kyverno CRDs (which the
  engine release installs in the same apply), avoiding the `kubernetes_manifest` chicken-and-egg.
- **Providers: `helm` + `aws`.** No `kubernetes` provider is required. The `aws` provider is used for
  the Kyverno **ECR-read IAM role + EKS Pod Identity association** (ADR-047) that lets the engine fetch
  cosign signatures when image verification is enabled.
- **Audit-first rollout.** `validation_failure_action = "Audit"` records violations as PolicyReports
  without blocking admission, and the generated webhook is fail-open (`failurePolicy: Ignore`).
  Flipping to `"Enforce"` rejects violations and fails the webhook closed (`Fail`). The flip is a
  one-line input change + apply.
- **Environment scoping.** Environment-targeted policies match the `platform.refplat.org/team` namespace
  label; infra namespaces are excluded. Cluster-scoped policies (RBAC, default-namespace) skip
  platform controllers via the `exclude_principals` allow-list.
- **Split with the Crossplane Environment Composition (ADR-046).** The **per-environment** image/hostname
  guardrails `restrict-images-<team>-<product>-<stage>` and `restrict-route-hostnames-<team>-<product>-<stage>`
  are provisioned by the Composition (one set per `XEnvironment` namespace, so the claim owns them). This module
  **keeps** owning the platform-wide floor and the per-**product** cosign/SLSA supply-chain policies
  `verify-images-product-<team>-<product>` / `verify-attestations-product-<team>-<product>` — signature/attestation
  trust roots are a platform security control, not a per-environment knob. Those derive from the **Product
  registry** (`gitops/products/`) via `verify_subjects_product` (the old `teams.hcl` / `verify_subjects` v2 inputs
  are retired).

## Phase 1 policy set

| ClusterPolicy | Kind(s) | Purpose |
| ------------- | ------- | ------- |
| `restrict-image-registries` | Pod | Environment images only from `allowed_registries` (cluster-wide ECR floor) |
| `disallow-latest-tag` | Pod | Require an explicit, non-`latest` tag |
| `require-requests-limits` | Pod | CPU/memory requests + limits on every container |
| `require-pod-probes` | Pod | Liveness + readiness probes |
| `restrict-automount-sa-token` | Pod | `automountServiceAccountToken: false` |
| `require-workload-labels` | Pod | Identity + cost-allocation labels |
| `block-public-loadbalancer` | Service | Deny `LoadBalancer`/`NodePort` (Gateway-only ingress) |
| `disallow-irsa-annotation-cross-team` | ServiceAccount | Deny environment IRSA annotations (until #64) |
| `restrict-binding-clusteradmin` | (Cluster)RoleBinding | Deny binding to `cluster-admin` |
| `restrict-wildcard-rbac` | Role, ClusterRole | Deny wildcard verbs/resources/apiGroups |
| `disallow-default-namespace` | Workloads | No workloads in `default` |
| `require-environment-namespace-naming` | Namespace | Environment namespaces named `<team>-<product>-<stage>` |
| `require-pod-security-restricted` | Pod | **hipaa/pci only** — full Restricted PSS |
| `require-ro-rootfs` | Pod | **hipaa/pci only** — read-only root filesystem |
| `disallow-privilege-escalation` | Pod | Deny `allowPrivilegeEscalation: true` (Phase 2 backstop) |
| `require-seccomp` | Pod | Deny `seccompProfile.type: Unconfined` (Phase 2 backstop) |

### Phase 2 mutate policies (`enable_mutate_defaults`, default true)

Auto-inject safe defaults on environment workloads (add-if-absent; webhooks fail open):
`mutate-pod-defaults` (allowPrivilegeEscalation=false, drop ALL caps, seccompProfile=RuntimeDefault,
automountServiceAccountToken=false, plus the ADR-085 graceful-drain defaults — a native `preStop`
sleep + `terminationGracePeriodSeconds: 30` — one patch so it resolves under autogen) and
`mutate-workload-labels` (`team`, derived from the namespace). Pair with ArgoCD `ignoreDifferences`
for the mutated fields. See the
[policy catalog](../../../docs/architecture/kyverno-policy-catalog.md#mutate-policies-phase-2).

### Availability: PodDisruptionBudget generation (`enable_pdb_generate`, default true)

`generate-workload-pdb` creates a `maxUnavailable: 1` PodDisruptionBudget (`<workload>-pdb`) for every
environment `Deployment`/`StatefulSet`, with a selector **copied from the workload's own
`spec.selector.matchLabels`** (ADR-085 W2) — label-convention-agnostic and correct per workload, where the
Crossplane Composition cannot be (its per-service axis has no matching pod label). `maxUnavailable: 1` is
drain-safe by construction: it never blocks a node drain (Karpenter consolidation, EKS upgrade, `platctl`
park) yet protects the replica floor once `replicas >= 2`. `synchronize: true` reconciles the PDB back if
edited or deleted. The template also installs a ClusterRole aggregated into Kyverno's **background
controller** (`rbac.kyverno.io/aggregate-to-background-controller`) so it can create the PDBs — without it
the policy admits but silently generates nothing.

### Availability: topology spread (`enable_topology_spread`, default true)

`mutate-topology-spread` injects `topologySpreadConstraints` (across `topology.kubernetes.io/zone` and
`kubernetes.io/hostname`) on environment `Deployment`/`StatefulSet` workloads when absent, so a workload's
replicas don't all land on one node/AZ (ADR-085). Like the PDB, the `labelSelector` is **derived from the
workload's own `spec.selector.matchLabels`** — which is why this rule matches the controller directly (not
the Pod via autogen), since a static patch can't know the selector. `whenUnsatisfiable: ScheduleAnyway` keeps
it a soft preference (never strands pods `Pending` on a small or scaling-from-zero cluster); `matchLabelKeys:
[pod-template-hash]` spreads each rollout revision independently. add-if-absent (the scaffolder skeleton's
explicit spread is never overridden), and it applies on admission — existing workloads pick it up on their
next deploy.

### Availability: prod replica floor (`enable_replica_floor`, default true)

`require-prod-replica-floor` requires `spec.replicas >= 2` on `Deployment`/`StatefulSet` in **prod-stage**
environment namespaces (`<team>-<product>-prod`) — a single replica can't be zero-downtime, and a
`maxUnavailable: 1` PDB plus topology spread are meaningless on it (ADR-085). Lower stages stay at 1 replica
for cost. Replicas are **validated, never mutated** (mutating them would fight the HPA and the prod overlay);
when using an HPA, set `minReplicas >= 2`. It has its own `replica_floor_failure_action` (default `Audit`) so
it rolls Audit-first even where the cluster-wide `validationFailureAction` is `Enforce` — flip to `Enforce`
after reviewing the Audit PolicyReports.

### Availability: Argo Rollouts support (`enable_rollout_kind`, default false)

When all workloads become Argo `Rollout`s ([ADR-056](../../../docs/adrs/056-progressive-delivery-and-safe-rollback.md)),
the three controller-kind availability policies above match `Deployment`/`StatefulSet` *by kind* and would
silently no-op on a `Rollout`. Setting `enable_rollout_kind = true` adds `argoproj.io/v1alpha1/Rollout` to their
matches (and the rollouts read-RBAC for the PDB backfill), and gives topology-spread a Rollout-specific rule
keyed on `rollouts-pod-template-hash` (Rollout pods carry that label, not `pod-template-hash`). Pod-level
policies (securityContext, preStop, image/cosign) already cover Rollout pods via ReplicaSet autogen, so they
need no change. **Default `false`**: a Kyverno rule naming a kind whose CRD is absent fails to create
(Kyverno #7839), so enable this **per cluster only after the `argo-rollouts` unit (CRDs) is applied** there.

### Platform services: cross-namespace DB secret sync (`enable_db_secret_sync`, default false)

A stateful platform Product ([ADR-081](../../../docs/adrs/081-platform-service-delivery.md)) runs its app in
an Environment namespace but its CNPG database — and the generated `<cluster>-app` credential Secret — in a
dedicated platform-database namespace (a database does not belong in the tenant sandbox). Kubernetes
`secretKeyRef` can't cross namespaces, so the `sync-platform-db-secret` policy clones that Secret into the app
namespace, `synchronize: true` (propagates CNPG password rotation) + `generateExisting: true` (back-fills the
already-provisioned database). Namespace pairs are declared per binding at the unit (`db_secret_sync_bindings`),
so the module carries no product-specific data. First consumer: Flagship
([ADR-099](../../../docs/adrs/099-feature-flags-platform-service.md)).

RBAC is cluster-scoped, bound to both Kyverno controllers with explicit ClusterRoleBindings (not aggregation
labels — the admission pre-flight authz check runs synchronously at policy admission, but aggregated
ClusterRoles reconcile asynchronously, which would race it). READ (`get/list/watch` on Secrets) is cluster-wide
because `generateExisting` enumerates triggers with a *cluster-scoped* list; it's read-only (Kyverno's
admission webhooks already observe every Secret). WRITE cannot be namespace-scoped either, for **two** reasons:
(1) *ordering* — the target Environment namespace and the platform-database source namespace are created
**downstream** of this policy unit (by Crossplane / ArgoCD delivery), so a namespace-scoped Role can't be
created eagerly here (a from-scratch bootstrap would fail `namespaces not found`); and (2) Kyverno's **generate
pre-flight authz check** issues a *name-less* SubjectAccessReview for `create/update/delete` on the target
Secret's namespace when the policy is admitted — a `resourceNames`-pinned grant fails that SAR, so Kyverno
rejects the policy (`background-controller requires permissions update,delete for v1/Secret in namespace …`).
So WRITE is a cluster-scoped ClusterRole with **un-name-scoped** verbs, mirroring `generate-pdb`; the
ClusterPolicy itself is what bounds which Secret is actually written (Kyverno only ever writes the one it names).

## Usage

```hcl
module "policy" {
  source = "../../modules/policy"

  validation_failure_action = "Audit" # flip to "Enforce" once PolicyReports are clean
  compliance_tier           = "standard"
  replica_count             = 3

  # Cluster-wide ECR floor; the per-Environment restrict-images/restrict-route-hostnames guardrails
  # are owned by the Crossplane Environment Composition (ADR-046), not this module.
  allowed_registries = ["829808296602.dkr.ecr.us-east-1.amazonaws.com"]

  helm_chart_version = "3.8.1"
  tags               = { Environment = "preprod", ManagedBy = "terraform" }
}
```

## Testing

Policies are unit-tested with the Kyverno CLI, cluster-free:

```bash
# Pin the CLI to the chart's appVersion (1.18.x)
infra/modules/policy/.kyverno-tests/run.sh
```

`run.sh` renders `policies-chart/` with `helm template` and runs `kyverno test` against the fixtures
in `.kyverno-tests/` (compliant workload passes; foreign-registry / `latest` / missing-limits /
cross-team IRSA / LoadBalancer resources are rejected).

## Break-glass

If a policy blocks legitimate admission, patch the generated webhook configurations to fail-open
(`failurePolicy: Ignore`) or delete them (Kyverno recreates on restart). See
`docs/runbooks/kyverno-break-glass.md`.

## Inputs

| Name | Description | Type | Default |
| ---- | ----------- | ---- | ------- |
| `create` | Whether to create resources | `bool` | `true` |
| `validation_failure_action` | `Audit` or `Enforce` | `string` | `"Audit"` |
| `compliance_tier` | `standard`/`hipaa`/`pci` | `string` | `"standard"` |
| `allowed_registries` | Registry prefixes admitted in environment namespaces | `list(string)` | `[]` |
| `verify_subjects_product` | Per-Product cosign/SLSA verification config, derived from `gitops/products/` | `map(object)` | `{}` |
| `exclude_namespaces` | Infra namespaces excluded from policies | `list(string)` | (see variables.tf) |
| `exclude_principals` | Principal wildcards skipped by cluster-scoped policies | `list(string)` | (see variables.tf) |
| `environment_namespace_label` | Namespace label marking environments | `string` | `"platform.refplat.org/team"` |
| `required_workload_labels` | Labels every workload must carry (presence validated; `team` is auto-injected) | `list(string)` | `["team"]` |
| `replica_count` | Admission controller replicas (HA=3) | `number` | `3` |
| `helm_chart_version` | Kyverno chart version | `string` | `"3.8.1"` |
| `additional_policies` | Raw ClusterPolicy YAML (ADR-014 escape hatch) | `map(string)` | `{}` |
| `enable_db_secret_sync` | Clone a CNPG DB Secret from a platform-database namespace into a platform Product's Environment namespace (ADR-099) | `bool` | `false` |
| `db_secret_sync_bindings` | Namespace pairs for `enable_db_secret_sync` (`{name, sourceNamespace, secretName, targetNamespace}`) | `list(object)` | `[]` |
| `tags` | Tags/labels | `map(string)` | `{}` |

## Outputs

| Name | Description |
| ---- | ----------- |
| `namespace` | Namespace where Kyverno is installed |
| `engine_status` | Helm status of the Kyverno engine release |
| `policies_status` | Helm status of the ClusterPolicies release |
| `validation_failure_action` | Effective policy action (Audit/Enforce) |

## Related

- **[Kyverno Policy Catalog](../../../docs/architecture/kyverno-policy-catalog.md)** — the per-cluster
  list of enforced policies (preprod / platform / prod) and their scope
- ADR-014: Kyverno as Policy Engine
- ADR-013: Compliance Tier Model
- ADR-027 / ADR-039 / ADR-040: Environment isolation, per-team RBAC, platform-engineer access
