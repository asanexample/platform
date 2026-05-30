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

- The **count differs** because per-team image policies (`restrict-images-team-<team>`) are generated
  one-per-tenant from `teams.hcl`. Preprod has tenants `alpha` + `bravo` (→ +2 policies); the platform
  cluster hosts shared services only (no tenants), so it has the 12 common policies.
- **Mode** is controlled by the unit's `validation_failure_action` (`Audit` records PolicyReports and
  fails the webhook open; `Enforce` rejects at admission and fails the webhook closed). The flip is a
  one-line input change + apply.

## Policies

**Scope** column:

- _tenant_ — matches only namespaces carrying the `platform.refplat.org/tenant` label (infra
  namespaces excluded). Inert on clusters with no tenant namespaces (e.g. platform).
- _cluster_ — evaluates cluster-wide at admission; skips the principals in `exclude_principals`
  (the IaC deployer, ArgoCD, and Kubernetes system controllers). These run `background: false`
  (Kyverno disallows `userInfo` in background scanning), so they only act on new `CREATE`/`UPDATE`.

| Policy | Target kind(s) | Enforces | Scope | Tier | Clusters |
| ------ | -------------- | -------- | ----- | ---- | -------- |
| `restrict-image-registries` | Pod | Images only from approved registries (the platform ECR) | tenant | all | preprod, platform |
| `restrict-images-team-<team>` | Pod | `team-<team>` namespace may only run `…/team-<team>/*` images (per-team, from `teams.hcl`) | tenant (per-team ns) | all | preprod (alpha, bravo) |
| `disallow-latest-tag` | Pod | Explicit, non-`latest` image tag required | tenant | all | preprod, platform |
| `require-requests-limits` | Pod | CPU + memory requests **and** limits on every container | tenant | all | preprod, platform |
| `require-pod-probes` | Pod | Liveness + readiness probes on every container | tenant | all | preprod, platform |
| `restrict-automount-sa-token` | Pod | `automountServiceAccountToken: false` | tenant | all | preprod, platform |
| `require-workload-labels` | Pod | `app.kubernetes.io/name` + `team` labels | tenant | all | preprod, platform |
| `block-public-loadbalancer` | Service | Deny `LoadBalancer` / `NodePort` (Gateway-only ingress) | tenant | all | preprod, platform |
| `disallow-irsa-annotation-cross-team` | ServiceAccount | Deny `eks.amazonaws.com/role-arn` annotation (until per-team IRSA, #64) | tenant | all | preprod, platform |
| `require-tenant-namespace-naming` | Namespace | Tenant namespaces named `team-*` | tenant (labelled ns) | all | preprod, platform |
| `restrict-binding-clusteradmin` | RoleBinding, ClusterRoleBinding | Deny binding to `cluster-admin` | cluster | all | preprod, platform |
| `restrict-wildcard-rbac` | Role, ClusterRole | Deny wildcard verbs / resources / apiGroups | cluster | all | preprod, platform |
| `disallow-default-namespace` | Pod, Deployment, StatefulSet, DaemonSet, ReplicaSet, Job, CronJob | No workloads in `default` | cluster | all | preprod, platform |
| `disallow-privilege-escalation` | Pod | Deny `securityContext.allowPrivilegeEscalation: true` (backstops the mutate default) | tenant | all | preprod, platform |
| `require-seccomp` | Pod | Deny `seccompProfile.type: Unconfined` (backstops the mutate default) | tenant | all | preprod, platform |
| `require-pod-security-restricted` | Pod | Full Restricted Pod Security Standard | tenant | **hipaa/pci only** | _(none yet — standard tier)_ |
| `require-ro-rootfs` | Pod | `readOnlyRootFilesystem: true` | tenant | **hipaa/pci only** | _(none yet — standard tier)_ |

The two tier-gated policies render only when a cluster's `compliance_tier` is `hipaa` or `pci`. Both
current clusters are `standard`, so they are not deployed there yet; they will appear automatically on
any cluster set to a regulated tier (e.g. a future prod). See [ADR-013](../adrs/013-compliance-tier-model.md).

## Mutate policies (Phase 2)

`mutate` policies auto-inject safe defaults on tenant workloads at admission (add-if-absent — never
overrides an explicit app value), so apps need no security boilerplate and still satisfy the validate
policies (Kyverno mutates before validating). Gated by `enable_mutate_defaults` (default true); the
mutate webhooks **fail open** (a missed default must never block a pod). Their security values are
_enforced_ by the `disallow-privilege-escalation` / `require-seccomp` validate backstops above, so the
matching ArgoCD `ignoreDifferences` is safe.

| Policy | Injects (when absent) | Scope |
| ------ | --------------------- | ----- |
| `mutate-pod-defaults` | container `securityContext` (`allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`; not `runAsNonRoot`) **and** pod `automountServiceAccountToken: false` — one patch so strategic-merge resolves under autogen | tenant |
| `mutate-workload-labels` | `team` (tenant key from the `team-<k>[-env]` namespace name) | tenant |

> `app.kubernetes.io/name` can't be auto-derived under autogen (pod templates have no name), so it is
> **recommended but not required** — `require-workload-labels` requires only `team`, which is
> auto-injected. Apps therefore need no label boilerplate.

ArgoCD is told to ignore the mutated sub-fields (`argocd_cm_extra` →
`resource.customizations.ignoreDifferences.all`) so selfHeal doesn't fight Kyverno.

## Image verification (Phase 3 — cosign keyless)

Gated by `enable_image_verification`; rolls Audit→Enforce via its **own** `verify_failure_action`
(independent of the validate/Enforce action above). App CI signs images keyless (GitHub Actions OIDC →
Fulcio/Rekor); Kyverno fetches the signature from ECR (via an IRSA role granting ECR read) and admits
only images signed by that team's workflow identity.

| Policy | Verifies | Scope |
| ------ | -------- | ----- |
| `verify-images-team-<team>` | Images under `…/team-<team>/*` are cosign-signed by `app-<team>`'s `deploy.yml@main` (pinned) **or** `preview.yml` (subjectRegExp — the PR OIDC ref varies); `mutateDigest` pins to digest | tenant (per-team) |

Per-team identity isolation: a signature from another team's workflow does **not** satisfy a team's
policy — the supply-chain analog of per-team registry scoping. Deployed on **preprod** (where tenants
run); the platform cluster has no tenant workloads. Verification depends on cluster egress to
sigstore (Fulcio/Rekor) — see the break-glass runbook.

## Exemptions (so the platform never blocks itself)

Configured on the module and applied to every cluster:

- **`exclude_namespaces`** (tenant policies skip these): `kube-system`, `kube-node-lease`,
  `kube-public`, `kyverno`, `cert-manager`, `external-secrets`, `external-dns`, `argocd`, `tailscale`.
- **`exclude_principals`** (cluster-scoped policies skip these usernames): the IaC deployer
  `arn:aws:sts::*:assumed-role/PlatformDeployer/*`, ArgoCD `system:serviceaccount:argocd:*`,
  `system:serviceaccount:kube-system:*`, `system:nodes:*`, `system:kube-controller-manager`.
  **PlatformAdmin is intentionally not exempt** — it is read+operate, not author (ADR-040).

## Adding a cluster (e.g. prod)

1. Add a `policy/terragrunt.hcl` unit under the env mirroring the existing ones (eks + node-groups
   deps, helm provider, `allowed_registries` from the platform ECR, `tenant_registry_map` from the
   env's `teams.hcl` if any, `compliance_tier` from `workload.hcl`).
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
