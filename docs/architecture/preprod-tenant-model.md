# Preprod Tenant Isolation Model

> Related: [ADR-027 — Hybrid Tenant Isolation](../adrs/027-hybrid-tenant-isolation.md)

## Overview

The preprod EKS cluster (`preprod-use1-eks`, account `620830101009`) supports two
tenant isolation modes on a single shared cluster:

- **Namespace mode** — lightweight isolation via Kubernetes namespaces,
  ResourceQuotas, LimitRanges, and Cilium NetworkPolicies.
- **vCluster mode** — full virtual control plane per tenant, with its own API
  server, etcd, and resource syncing to a host namespace.

Teams declare their mode in `teams.hcl`. That single file drives namespace
creation, EKS access entries, vCluster deployments, and ArgoCD app targeting.

## Architecture Diagram

### Namespace mode (team-alpha)

```text
Internet
  |
  v
+------------------+
|   AWS NLB        |  (created by Cilium GatewayClass)
+------------------+
  |
  v
+------------------------------------------+
| Gateway: preprod-gateway  (ns: default)  |
| GatewayClass: cilium                     |
| Listeners: HTTPS :443, HTTP :80          |
| allowedRoutes.namespaces.from: All       |
+------------------------------------------+
  |
  v
+------------------------------------------+
| HTTPRoute        (ns: team-alpha)        |
| parentRef: preprod-gateway/default       |
| hostname: alpha.preprod.aws.refplat.org  |
+------------------------------------------+
  |
  v
+------------------------------------------+
| Service          (ns: team-alpha)        |
+------------------------------------------+
  |
  v
+------------------------------------------+
| Pod              (ns: team-alpha)        |
| NetworkPolicy: default-deny-ingress     |
|                + allow-gateway-ingress   |
|                + allow-dns-egress        |
+------------------------------------------+
```

### vCluster mode (team-bravo)

```text
Internet
  |
  v
+------------------+
|   AWS NLB        |
+------------------+
  |
  v
+------------------------------------------+
| Gateway: preprod-gateway  (ns: default)  |
+------------------------------------------+
  |
  v
+------------------------------------------+
| HTTPRoute        (ns: vc-bravo)          |
| synced from vCluster via generic sync    |
| hostname: bravo.preprod.aws.refplat.org  |
+------------------------------------------+
  |
  v
+------------------------------------------+
| Service          (ns: vc-bravo)          |  <-- synced from virtual cluster
+------------------------------------------+
  |
  v
+------------------------------------------+
| Pod              (ns: vc-bravo)          |  <-- scheduled on host nodes
| isolation.enabled policies (vCluster)    |
+------------------------------------------+

  vCluster control plane (in vc-bravo):
  +--------------------------------------+
  | vcluster syncer  (StatefulSet)       |
  | virtual API server + etcd            |
  | generic sync: HTTPRoute v -> host    |
  +--------------------------------------+
```

## Namespace Mode Detail

The `tenant` module (`infra/modules/tenant/`) creates these resources for each
team with `mode = "namespace"`:

| Resource | Name | Purpose |
|----------|------|---------|
| `Namespace` | `team-<name>` | Workload boundary |
| `ResourceQuota` | `tenant-quota` | CPU, memory, and pod caps |
| `LimitRange` | `tenant-limits` | Default container requests/limits |
| `NetworkPolicy` | `default-deny-ingress` | Block all inbound traffic by default |
| `NetworkPolicy` | `allow-gateway-ingress` | Permit traffic from the Gateway namespace |
| `NetworkPolicy` | `allow-dns-egress` | Allow DNS (UDP/TCP 53) and internet egress |

Pods are isolated by namespace. Cilium enforces NetworkPolicies at the eBPF
level -- there is no iptables fallback. Cross-namespace traffic is blocked
unless an explicit policy allows it.

Gateway routing works because the `preprod-gateway` listener sets
`allowedRoutes.namespaces.from: All`. Any namespace can create an HTTPRoute
referencing the gateway. The `allow-gateway-ingress` NetworkPolicy permits
ingress from pods in the gateway namespace (`default`), where Cilium's
Envoy proxy runs.

## vCluster Mode Detail

For teams with `mode = "vcluster"`, the tenant module delegates to the
`vcluster` module (`infra/modules/vcluster/`), which:

1. Creates host namespace `vc-<name>`.
2. Deploys the vCluster Helm chart (chart `vcluster`, repo `charts.loft.sh`,
   version `0.24.1`) into that namespace.
3. Enables `isolation.enabled`, which creates vCluster-managed NetworkPolicies,
   LimitRanges, and ResourceQuotas on the host namespace.
4. Configures generic resource sync for `HTTPRoute` (`gateway.networking.k8s.io/v1`)
   from virtual to host cluster.

### How HTTPRoute sync works

The vCluster syncer watches HTTPRoute resources inside the virtual cluster and
creates corresponding HTTPRoute resources in the host namespace (`vc-<name>`).
Because the gateway listener accepts routes from all namespaces, these synced
HTTPRoutes attach to `preprod-gateway` and receive traffic through the shared
NLB. Backend Services and Pods are also synced to the host namespace by
vCluster's standard sync, so the Gateway data plane can reach them directly.

### kubeconfig access

Each vCluster generates a kubeconfig stored in secret `vc-<name>` in the host
namespace. Developers with `DeveloperAccess` (scoped to `vc-<name>`) can
retrieve it:

```bash
kubectl -n vc-bravo get secret vc-bravo -o jsonpath='{.data.config}' | base64 -d
```

Or use the vCluster CLI:

```bash
vcluster connect bravo -n vc-bravo
```

## Network Topology

### Namespace mode policies

The tenant module creates three NetworkPolicies per namespace:

**default-deny-ingress** -- Matches all pods, blocks all ingress. This is the
baseline; everything is denied unless another policy explicitly allows it.

```yaml
spec:
  podSelector: {}          # all pods
  policyTypes: [Ingress]
  # no ingress rules = deny all
```

**allow-gateway-ingress** -- Permits ingress from the gateway namespace so
Cilium's Envoy proxy can forward requests to tenant pods.

```yaml
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: default    # gateway namespace
```

**allow-dns-egress** -- Permits DNS resolution (port 53 UDP/TCP) and general
internet egress. This is a single policy with two egress rules.

```yaml
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - ports: [{port: 53, protocol: UDP}, {port: 53, protocol: TCP}]
  - to: [{ipBlock: {cidr: 0.0.0.0/0}}]
```

### vCluster mode policies

vCluster's built-in `isolation.enabled` creates its own set of NetworkPolicies
in the host namespace (`vc-<name>`). These policies restrict the syncer and
workload pods. The platform does not layer additional custom policies on top --
vCluster manages isolation end-to-end within the host namespace.

## Resource Governance

### Defaults

| Resource | Default |
|----------|---------|
| `requests.cpu` / `limits.cpu` | 4 cores |
| `requests.memory` / `limits.memory` | 8Gi |
| `pods` | 20 |
| Container default limit | 500m CPU, 512Mi memory |
| Container default request | 100m CPU, 128Mi memory |

### Per-team overrides

The `tenants` variable accepts per-team `resource_quota` overrides:

```hcl
# in the tenants live unit inputs
tenants = {
  alpha = {
    mode = "namespace"
    resource_quota = {
      cpu    = "8"
      memory = "16Gi"
      pods   = 40
    }
  }
}
```

For vCluster tenants, resource limits are managed by vCluster's built-in
`isolation.resourceQuota` and `isolation.limitRange` settings, both enabled
by default in the module.

## teams.hcl as Single Source of Truth

`infra/live/aws/preprod/us-east-1/platform/teams.hcl` defines every team and
its isolation mode. Multiple Terragrunt units read this file to derive their
inputs:

```text
+---------------------------+
|  teams.hcl                |
|  alpha: mode=namespace    |
|  bravo: mode=vcluster     |
+-----------+---------------+
            |
            |  read_terragrunt_config()
            |
   +--------+--------+------------------+
   |                  |                  |
   v                  v                  v
 eks/               tenants/         (future: argocd-apps/)
 terragrunt.hcl     terragrunt.hcl   terragrunt.hcl
   |                  |                  |
   v                  v                  v
 EKS access        Namespaces,        ArgoCD Application
 entries            ResourceQuotas,    per team targeting
                    NetworkPolicies,   preprod cluster
                    vClusters
```

**EKS access entries** (`eks/terragrunt.hcl`): The `DeveloperAccess` role gets
an `AmazonEKSEditPolicy` access entry scoped to each team's namespace:

- Namespace teams: `team-<name>` (e.g., `team-alpha`)
- vCluster teams: `vc-<name>` (e.g., `vc-bravo`)

**Tenant resources** (`tenants/terragrunt.hcl`): Reads `teams.hcl`, splits by
mode, and passes to the tenant module. The module creates namespace-mode
resources directly and delegates vCluster-mode teams to the vCluster sub-module.

**ArgoCD apps** (platform cluster): ArgoCD on the platform cluster creates
Application resources targeting the preprod cluster. Each team's `repo_url`
and `repo_path` from `teams.hcl` define the GitOps source; the destination
namespace is derived from the team name and mode.

### Adding a new team

1. Add an entry to `teams.hcl`:

   ```hcl
   charlie = {
     mode      = "namespace"
     repo_url  = "https://github.com/gangster/app-charlie"
     repo_path = "k8s/preprod"
   }
   ```

2. Run `terragrunt apply` in `eks/` (updates access entries) and `tenants/`
   (creates namespace + policies).
3. The ArgoCD Application is created automatically on the next sync.

## Security Boundaries

### What namespace mode protects against

- **Cross-tenant network traffic** -- Default-deny ingress with Cilium
  enforcement. Pods in `team-alpha` cannot receive traffic from `team-bravo`.
- **Resource exhaustion** -- ResourceQuota caps CPU, memory, and pod count.
  LimitRange sets defaults so pods without explicit requests still get bounded.
- **Unauthorized API access** -- `DeveloperAccess` EKS access entry is scoped
  to the team's namespace via `AmazonEKSEditPolicy`. Developers cannot list or
  modify resources in other namespaces.

### What namespace mode does NOT protect against

- **Kernel-level exploits** -- Namespaces share the host kernel. A container
  escape grants access to the node and all co-located tenants.
- **Noisy-neighbor I/O** -- ResourceQuota does not cap disk or network I/O.
  A pod performing heavy disk writes can degrade node performance.
- **CRD visibility** -- Cluster-scoped resources (CRDs, ClusterRoles, Nodes)
  are visible to anyone with list permissions at the cluster scope.

### What vCluster mode adds

- **Full API server isolation** -- Each tenant gets a virtual API server. CRDs,
  RBAC, namespaces, and admission webhooks are scoped to the virtual cluster.
  Tenants can install their own operators without affecting others.
- **Stronger blast radius** -- A misconfigured admission webhook or runaway
  controller only impacts the virtual cluster, not the host.
- **Independent RBAC** -- Tenants can create ClusterRoles and
  ClusterRoleBindings inside their virtual cluster without host-level impact.

### What vCluster mode does NOT protect against

- **Kernel-level exploits** -- Same as namespace mode; pods still run on shared
  host nodes.
- **Resource exhaustion beyond quotas** -- vCluster's built-in quotas apply, but
  I/O and network bandwidth are still shared.
- **Host namespace breakout** -- If a tenant can exec into the syncer pod or
  access the host namespace service account, they could escalate.

### When to use which

| Criteria | Namespace | vCluster |
|----------|-----------|----------|
| Team needs custom CRDs / operators | No | Yes |
| Team needs cluster-admin inside their env | No | Yes |
| Minimal overhead, fast provisioning | Yes | No |
| Cost sensitivity (no extra API server) | Yes | No |
| Regulatory requirement for control-plane separation | No | Yes |
