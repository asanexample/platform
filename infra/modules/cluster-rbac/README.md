# Cluster RBAC

Creates cluster-scoped Kubernetes RBAC for the **platform-operator** role: a `ClusterRole` granting
the debug and operational verbs that platform engineers need, bound (via `ClusterRoleBinding`) to a
Kubernetes group that the EKS access entry maps the `PlatformAdmin` principal to.

This is the "operate, don't author" half of the platform-engineer access model (ADR-040). Broad
read comes from the AWS-managed `AmazonEKSViewPolicy` associated with the same access entry, so this
ClusterRole only adds the **delta** View lacks:

- **Debug:** `pods/log` (get), `pods/exec` (create), `pods/portforward` (create)
- **Operate:** `pods` (delete), `pods/eviction` (create — drain), `nodes` (get/list/watch + patch —
  cordon/drain; View doesn't grant cluster-scoped node read),
  `deployments`/`statefulsets`/`daemonsets` (patch — `kubectl rollout restart`)

It deliberately grants **no `create`** and no other resource types. Resource authoring flows through
GitOps (ArgoCD); emergencies use break-glass (`OrganizationAccountAccessRole`).

> Note: RBAC verbs are not field-level — `patch` on nodes/workloads technically permits arbitrary
> patches to those objects, not just cordon/restart. For ArgoCD-managed resources, manual drift is
> reverted by ArgoCD self-heal, so GitOps remains the source of truth.

## Usage

```hcl
module "cluster_rbac" {
  source = "../../modules/cluster-rbac"

  # Must match the kubernetes_groups set on the PlatformAdmin EKS access entry.
  group_name = "platform-operators"
}
```

## Examples

### Disabled Module

```hcl
module "cluster_rbac" {
  source = "../../modules/cluster-rbac"
  create = false
}
```

## Notes

- Requires a configured `kubernetes` provider (the live unit generates one targeting the cluster).
- The `group_name` **must match** the `kubernetes_groups` value on the `PlatformAdmin` access entry
  in the `eks` unit, or the binding grants nothing.
- Cluster-scoped: one `ClusterRole` + one `ClusterRoleBinding` per cluster.

## Related ADRs

- ADR-040: Platform Engineer Access Model
- ADR-007: Platform IAM Role Model
