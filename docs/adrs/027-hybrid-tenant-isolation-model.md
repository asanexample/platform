# ADR-027: Hybrid Tenant Isolation Model

**Date:** 2026-05-27

**Status:** Accepted (vCluster mode deferred — see ADR-033)

## Context

The preprod EKS cluster (account <PREPROD_ACCOUNT_ID>) needs multi-tenant isolation for development teams.
The initial scope is 2-3 teams, each with their own Git repository and application deployments.
Teams will need public-facing ingress via the shared Gateway API Gateway (ADR-017).

Tenant isolation requirements vary significantly across teams:

1. **Simple applications.** Some teams deploy stateless services with no custom CRDs, no cluster-
   scoped resources, and no special scheduling requirements. For these teams, namespace-level
   isolation with NetworkPolicy enforcement is sufficient and operationally lightweight.

2. **Complex applications.** Other teams need CRD independence (custom operators, service meshes),
   cluster-admin-like permissions within their boundary, or stronger blast-radius containment. For
   these teams, namespace isolation is insufficient — a misbehaving CRD controller in one namespace
   can affect the entire host cluster.

The platform uses Cilium as CNI (ADR-008), which provides kernel-level NetworkPolicy enforcement
via eBPF. A vCluster module already exists at `infra/modules/vcluster/` with support for
isolation settings, resource quotas, limit ranges, and generic resource sync (HTTPRoute sync to
host cluster for ingress). The DeveloperAccess IAM role (ADR-007) provides namespace-scoped EKS
access entries for team members.

The key tension is between operational simplicity (one model for all teams) and right-sizing
isolation (teams should not pay overhead they don't need).

### Alternatives Considered

**1. Namespace-only with Cilium NetworkPolicy.** Every team gets a namespace with ResourceQuota,
LimitRange, and Cilium NetworkPolicy (default-deny ingress, allow from Gateway namespace). This
is the simplest model — one Kubernetes namespace per team, no additional control planes. However,
it provides no CRD isolation (a team installing a CRD affects the entire cluster), no
cluster-scoped resource separation, and no independent RBAC hierarchy. Teams needing stronger
isolation would have to accept shared-cluster compromises or escalate to a separate EKS cluster.

**2. vCluster-only for all teams.** Every team gets a virtual cluster deployed via the vCluster
module. Consistent isolation model — every team gets its own API server, CRD space, and RBAC
hierarchy. However, each vCluster instance runs a syncer and virtual API server consuming
approximately 256Mi memory and 100m CPU at idle. For teams deploying a single stateless service,
this overhead is unnecessary. With 10+ teams, the aggregate resource consumption becomes
significant on the shared node groups. The operational complexity of managing virtual cluster
lifecycles, version upgrades, and debugging syncer issues is also disproportionate for simple
workloads.

**3. Separate EKS clusters per team.** Strongest possible isolation — each team gets a dedicated
EKS cluster with its own control plane, node groups, and CNI deployment. This eliminates all
multi-tenancy concerns but creates massive cost and operational overhead. Each EKS cluster costs
$0.10/hr ($73/mo) for the control plane alone, plus dedicated node groups, CNI deployment
(ADR-009 requires 4 Terragrunt units per cluster), and independent platform service stacks
(cert-manager, external-dns, external-secrets). For 2-3 teams in preprod, this is at least 3x
the infrastructure cost and operational burden. The deployment dependency graph (CLAUDE.md)
would need to be replicated per team.

**4. Hybrid model with per-team mode selection (chosen).** Teams declare their isolation mode in
a central `teams.hcl` configuration. Simple teams get namespace isolation; teams needing CRD
independence or stronger blast-radius containment get a vCluster. Both modes share the same
host cluster infrastructure (node groups, CNI, Gateway) and the same ingress path (Gateway API).

## Decision

Adopt a hybrid tenant isolation model where each team's isolation level is declared in
`infra/live/aws/preprod/us-east-1/platform/teams.hcl` and enforced by the `infra/modules/tenant/`
module. Teams choose between two modes:

### Mode: Namespace

For teams with simple application deployments that do not need CRD isolation.

The tenant module creates:

- **Namespace** `team-<name>` with labels identifying the tenant and mode
- **ResourceQuota** with configurable limits (default: 4 CPU, 8Gi memory, 20 pods)
- **LimitRange** with container defaults (request: 100m CPU / 128Mi memory, limit: 500m CPU /
  512Mi memory) to prevent unbounded resource consumption by pods without explicit limits
- **NetworkPolicy (default-deny ingress)** — blocks all inbound traffic to the namespace by
  default
- **NetworkPolicy (allow gateway ingress)** — permits traffic from the Gateway namespace and
  `kube-system` so that HTTPRoutes can reach backend services
- **CiliumNetworkPolicy (allow gateway envoy)** — permits traffic from the Cilium `ingress`,
  `remote-node`, and `host` entities. Required because Cilium's Gateway API Envoy proxy uses the
  reserved `ingress` identity (not `host`) for upstream connections to backend pods (ADR-008).
  Standard Kubernetes NetworkPolicy cannot match this identity.
- **NetworkPolicy (allow DNS + internet egress)** — permits DNS resolution (UDP/TCP port 53) and
  outbound internet access for external API calls, **except** the instance metadata endpoint
  (`169.254.169.254/32`), so a tenant pod cannot steal the node IAM role's credentials
- **Pod Security Admission labels** — `enforce=baseline` (blocks privileged, hostPath,
  hostNetwork/PID, and host ports — the node-escape vectors) with `warn=restricted`/`audit=restricted`
  to surface stricter violations without breaking current workloads
- **Developer RBAC** — a per-namespace `RoleBinding` binding the team's developer group
  (`team-<name>:developers`) to the cluster-wide `tenant-developer` role (see ADR-039)

Cilium enforces these policies at the eBPF level (ADR-008), providing kernel-level network
segmentation without iptables overhead.

### Mode: vCluster (Deferred)

> **Note:** vCluster mode is deferred as of ADR-033. The open-source vCluster chart does not
> support syncing custom resources (like HTTPRoute) from the virtual cluster to the host cluster
> — this feature requires the vCluster Platform operator (Free tier) with a connection to Loft's
> license server. Without HTTPRoute sync, vCluster tenants cannot route traffic through the
> shared Gateway API Gateway, making apps unreachable from the internet. All teams currently use
> namespace mode. The vCluster module is retained for future use.

For teams that need CRD independence, cluster-admin-like permissions, or stronger blast-radius
containment.

The tenant module can deploy a vCluster instance via the `infra/modules/vcluster/` module:

- **Namespace** `vc-<name>` on the host cluster for the vCluster control plane
- **Virtual API server** running as a StatefulSet in the host namespace
- **Policies** — vCluster's built-in policy enforcement activates resource quotas, limit
  ranges, and network policies within the virtual cluster
- **CRD independence** — each vCluster has its own CRD registry, so team-installed operators and
  custom resources do not affect the host cluster or other tenants
- **Limitation** — HTTPRoute sync from virtual to host cluster requires vCluster Pro/Free tier
  (not available in OSS). Without it, apps are only reachable via `vcluster connect` or
  port-forward.

### Team Declaration

Teams are declared in `teams.hcl` at the environment level:

```hcl
locals {
  teams = {
    alpha = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/gangster/app-alpha"
          repo_path = "k8s/preprod"
          preview   = true
        }
      }
    }
    bravo = {
      mode = "namespace"
      apps = {
        demo = {
          repo_url  = "https://github.com/gangster/app-bravo"
          repo_path = "k8s/preprod"
          preview   = false
        }
      }
    }
  }
}
```

> **Note:** The data model was updated from one-app-per-team to multi-app in
> ADR-031. Each team now has a nested `apps` map. The `preview` flag enables
> PR preview environments (ADR-032).

The `tenants` Terragrunt unit reads this file and passes the team map to the tenant module. Mode
selection filters happen inside the module — `namespace_tenants` and `vcluster_tenants` are
computed from the same input map, so adding a team or changing a team's mode is a single-line
change in `teams.hcl`.

### EKS Access

Each team has its own `DeveloperAccess-<team>` IAM role (ADR-039). For namespace-mode tenants, the
team's EKS access entry maps that role to the Kubernetes group `team-<name>:developers`, which the
tenant module binds — via a namespace-scoped `RoleBinding` — to the `tenant-developer` role in the
team's namespace only. A developer can therefore edit only their own namespace, and can assume only
their own team's role. For vCluster-mode tenants, developers interact with the virtual cluster's API
server directly — they do not need host cluster access. The vCluster kubeconfig is generated from the
vCluster's service account token.

### Ingress Path

Both modes share the same Gateway API Gateway (ADR-017):

```text
Internet → NLB → Cilium Gateway → HTTPRoute → Backend Service
```

For namespace-mode tenants, HTTPRoutes are created directly in the tenant namespace (or in the
Gateway namespace with backend references). For vCluster-mode tenants, HTTPRoute sync would
require the vCluster Platform operator (Free tier), which is not currently deployed — see
ADR-033 for details on this limitation.

### Deployment Dependencies

The `tenants` unit depends on `eks`, `node-groups`, and `gateway-config`, ensuring the cluster,
CNI, nodes, and Gateway are all ready before tenant resources are created.

## Consequences

### Positive

- Right-sized isolation — teams pay only the overhead their workload requires. Simple apps get
  lightweight namespace separation; complex apps get full virtual cluster isolation.
- Single configuration surface — `teams.hcl` is the authoritative source for team definitions.
  Adding a team or changing its isolation mode is a one-line change, not a new Terragrunt unit.
- Shared infrastructure — both modes use the same node groups, CNI, and Gateway, avoiding the
  cost and operational overhead of per-team clusters.
- Consistent ingress — both modes route through the same Gateway API Gateway, so DNS, TLS, and
  load balancing configuration is managed once by the platform team.
- Incremental adoption — teams can start in namespace mode and graduate to vCluster mode if their
  requirements grow, without changing their application manifests (only the `mode` field in
  `teams.hcl`). Note: vCluster mode is currently deferred (ADR-033) due to HTTPRoute sync
  requiring vCluster Pro/Free tier.

### Negative

- Two isolation models to document, monitor, and support. Platform engineers must understand
  both namespace isolation semantics and vCluster syncer behavior.
- Two kubectl access patterns — namespace-mode teams use `aws eks get-token` with namespace-
  scoped RBAC; vCluster-mode teams use vCluster-generated kubeconfigs. Onboarding documentation
  must cover both paths.
- vCluster HTTPRoute sync adds a layer of indirection — debugging ingress issues for vCluster
  tenants requires inspecting both the virtual and host cluster states.
- The tenant module mixes Kubernetes-native resources (namespace, ResourceQuota, NetworkPolicy)
  with Helm-based deployments (vCluster), creating two different lifecycle management patterns
  within the same module.

### Risks

- A vCluster syncer bug could leak resources to the host cluster or fail to sync HTTPRoutes,
  breaking ingress for that tenant. Mitigated by pinning the vCluster chart version and testing
  upgrades in a non-production vCluster first.
- Namespace-mode tenants share the host cluster's CRD space and node pool. Pod Security Admission
  (`enforce=baseline`) blocks the privileged/hostPath/hostNetwork pods that would let a tenant escape
  to a node, and developer RBAC is namespace-scoped (cannot create cluster-scoped resources or CRDs).
  Richer policy (image provenance/per-team registry scoping, RBAC hardening, cross-team IRSA guard)
  is provided by **Kyverno (ADR-014), now deployed (Phase 1)** layered above the PSA `baseline` floor.
- ResourceQuota defaults (4 CPU, 8Gi, 20 pods) may be too restrictive for some teams or too
  generous for others. These are configurable per-team via the `resource_quota` field in the
  tenant map, but require platform team intervention to adjust.
- If the number of vCluster tenants grows beyond 5-10, the aggregate resource consumption of
  virtual API servers may require dedicated node groups or resource reservations to prevent
  contention with namespace-mode workloads.
