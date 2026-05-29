# Policy (Kyverno)

Deploys the [Kyverno](https://kyverno.io/) policy engine and the platform's admission-control
ClusterPolicies on a Kubernetes cluster (ADR-014). Kyverno layers above the Pod Security Admission
`baseline` floor (ADR-027/040) to express controls PSA cannot: per-tenant image-registry scoping,
cross-team IRSA-annotation prevention, RBAC hardening, resource/label requirements, and tier-gated
restricted Pod Security.

The module is **cloud-agnostic and holds no team-specific data** — per-tenant values
(`tenant_registry_map`, `allowed_registries`) are supplied by the Terragrunt unit from `teams.hcl`.

## Design

- **Two Helm releases.** `helm_release.kyverno` installs the engine (HA admission controller);
  `helm_release.policies` installs a bundled local chart (`policies-chart/`) of our ClusterPolicies
  and `depends_on` the engine. A local chart needs no plan-time access to the Kyverno CRDs (which the
  engine release installs in the same apply), avoiding the `kubernetes_manifest` chicken-and-egg.
- **Helm-only provider.** No `kubernetes` provider is required.
- **Audit-first rollout.** `validation_failure_action = "Audit"` records violations as PolicyReports
  without blocking admission, and the generated webhook is fail-open (`failurePolicy: Ignore`).
  Flipping to `"Enforce"` rejects violations and fails the webhook closed (`Fail`). The flip is a
  one-line input change + apply.
- **Tenant scoping.** Tenant-targeted policies match the `platform.refplat.org/tenant` namespace
  label; infra namespaces are excluded. Cluster-scoped policies (RBAC, default-namespace) skip
  platform controllers via the `exclude_principals` allow-list.

## Phase 1 policy set

| ClusterPolicy | Kind(s) | Purpose |
| ------------- | ------- | ------- |
| `restrict-image-registries` | Pod | Tenant images only from `allowed_registries` (ECR floor) |
| `restrict-images-team-<k>` | Pod | `team-<k>` namespace may only run images under its own prefix |
| `disallow-latest-tag` | Pod | Require an explicit, non-`latest` tag |
| `require-requests-limits` | Pod | CPU/memory requests + limits on every container |
| `require-pod-probes` | Pod | Liveness + readiness probes |
| `restrict-automount-sa-token` | Pod | `automountServiceAccountToken: false` |
| `require-workload-labels` | Pod | Identity + cost-allocation labels |
| `block-public-loadbalancer` | Service | Deny `LoadBalancer`/`NodePort` (Gateway-only ingress) |
| `disallow-irsa-annotation-cross-team` | ServiceAccount | Deny tenant IRSA annotations (until #64) |
| `restrict-binding-clusteradmin` | (Cluster)RoleBinding | Deny binding to `cluster-admin` |
| `restrict-wildcard-rbac` | Role, ClusterRole | Deny wildcard verbs/resources/apiGroups |
| `disallow-default-namespace` | Workloads | No workloads in `default` |
| `require-tenant-namespace-naming` | Namespace | Tenant namespaces named `team-*` |
| `require-pod-security-restricted` | Pod | **hipaa/pci only** — full Restricted PSS |
| `require-ro-rootfs` | Pod | **hipaa/pci only** — read-only root filesystem |

## Usage

```hcl
module "policy" {
  source = "../../modules/policy"

  validation_failure_action = "Audit" # flip to "Enforce" once PolicyReports are clean
  compliance_tier           = "standard"
  replica_count             = 3

  allowed_registries  = ["829808296602.dkr.ecr.us-east-1.amazonaws.com"]
  tenant_registry_map = {
    alpha = "829808296602.dkr.ecr.us-east-1.amazonaws.com/team-alpha"
    bravo = "829808296602.dkr.ecr.us-east-1.amazonaws.com/team-bravo"
  }

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
| `allowed_registries` | Registry prefixes admitted in tenant namespaces | `list(string)` | `[]` |
| `tenant_registry_map` | tenant key → allowed image prefix | `map(string)` | `{}` |
| `exclude_namespaces` | Infra namespaces excluded from policies | `list(string)` | (see variables.tf) |
| `exclude_principals` | Principal wildcards skipped by cluster-scoped policies | `list(string)` | (see variables.tf) |
| `tenant_namespace_label` | Namespace label marking tenants | `string` | `"platform.refplat.org/tenant"` |
| `required_workload_labels` | Labels every workload must carry | `list(string)` | `["app.kubernetes.io/name", "team"]` |
| `replica_count` | Admission controller replicas (HA=3) | `number` | `3` |
| `helm_chart_version` | Kyverno chart version | `string` | `"3.8.1"` |
| `additional_policies` | Raw ClusterPolicy YAML (ADR-014 escape hatch) | `map(string)` | `{}` |
| `tags` | Tags/labels | `map(string)` | `{}` |

## Outputs

| Name | Description |
| ---- | ----------- |
| `namespace` | Namespace where Kyverno is installed |
| `engine_status` | Helm status of the Kyverno engine release |
| `policies_status` | Helm status of the ClusterPolicies release |
| `validation_failure_action` | Effective policy action (Audit/Enforce) |

## Related ADRs

- ADR-014: Kyverno as Policy Engine
- ADR-013: Compliance Tier Model
- ADR-027 / ADR-039 / ADR-040: Tenant isolation, per-team RBAC, platform-engineer access
