# Preprod Tenant Isolation Model

> Related: [ADR-027 — Hybrid Tenant Isolation](../adrs/027-hybrid-tenant-isolation-model.md),
> [ADR-033 — Defer vCluster Support](../adrs/033-defer-vcluster-tenant-support.md),
> [ADR-041 — Pod Identity for Tenant Workloads](../adrs/041-pod-identity-for-tenant-workloads.md),
> [ADR-046 — BACK stack for developer self-service](../adrs/046-back-stack-for-developer-self-service.md),
> [ADR-047 — Pod Identity standard](../adrs/047-pod-identity-standard.md),
> [ADR-049 — Multi-tenancy model (Team / Tenant / Zone)](../adrs/049-tenant-model-team-tenant-zone.md)

<!-- -->

> **Current model is `team == tenant`; the target model is ADR-049.** This document describes the **current**
> preprod tenant model, where one team is one tenant is one namespace. The matured, scale/compliance/multi-cloud
> model — **Team → Tenant → Zone** (ownership decoupled from isolation; a compliance-driven isolation spectrum
> up to dedicated cluster/account; cloud-neutral placement with data residency) — is
> [ADR-049](../adrs/049-tenant-model-team-tenant-zone.md). ADR-049 is **design-stage** and lands with the
> planned rebuild, so everything below still describes how preprod runs **today**.

<!-- -->

> **Provisioning is now Crossplane.** This document describes the tenant
> *isolation model* — what a tenant looks like on the cluster (namespace mode,
> NetworkPolicies, RBAC, quotas, Pod Identity). That model is unchanged. What
> changed is **how a tenant is provisioned**: tenants are now a single
> declarative **`Tenant` claim** (`XTenant`) reconciled by a Crossplane
> **Composition** (BACK stack P3, #174). Both teams (alpha, bravo) are migrated.
> The previous Terragrunt path — the `infra/modules/tenant` module and the
> `tenants`/`pod-identity` units — is **retired and deleted**. For the claim API
> (XRD schema, Composition pipeline, claim lifecycle, federated topology) see
> [Crossplane Tenant API](crossplane-tenant-api.md). Where this doc says "the
> tenant module creates …", read it as "the Composition provisions …" — the
> resulting cluster footprint is the same.

## Overview

The preprod EKS cluster (`preprod-use1-eks`, account `<PREPROD_ACCOUNT_ID>`) uses
**namespace-based tenant isolation** on a shared cluster. Each team gets a
dedicated namespace with ResourceQuotas, LimitRanges, and Cilium NetworkPolicies.

Each team is one **`XTenant` claim**; a Crossplane Composition reconciles it into
the namespace, RBAC, quotas, NetworkPolicies, per-team Kyverno guardrails, Pod
Identity, and cross-account ECR. ArgoCD syncs the claim YAMLs from
`gitops/tenant-claims/<env>/`. See [Crossplane Tenant API](crossplane-tenant-api.md).

> **Note:** The tenant module also supports a vCluster mode for stronger isolation
> (CRD independence, virtual control plane), but this is **deferred** (ADR-033).
> The open-source vCluster chart cannot sync HTTPRoute resources to the host
> cluster's Gateway, making vCluster tenants unreachable from the internet.
> All teams currently use namespace mode.

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
| CiliumNetworkPolicy: allow-gateway-envoy|
+------------------------------------------+
```

### Namespace mode (team-bravo)

Same architecture as team-alpha. Both teams use namespace isolation.

> **vCluster mode** is supported by the tenant module but currently deferred
> (ADR-033) because HTTPRoute sync from virtual to host cluster requires the
> vCluster Platform operator (not available in the open-source chart).

## Namespace Mode Detail

The Crossplane Tenant Composition provisions these resources for each team (the
retired `tenant` module created the same set for `mode = "namespace"`):

| Resource | Name | Purpose |
|----------|------|---------|
| `Namespace` | `team-<name>` | Workload boundary |
| `ResourceQuota` | `tenant-quota` | CPU, memory, pod, service/LB, PVC, and storage caps |
| `LimitRange` | `tenant-limits` | Default container requests/limits |
| `NetworkPolicy` | `default-deny-ingress` | Block all inbound traffic by default |
| `NetworkPolicy` | `allow-gateway-ingress` | Permit traffic from the Gateway and kube-system namespaces |
| `CiliumNetworkPolicy` | `allow-gateway-envoy` | Permit traffic from Cilium `ingress`, `remote-node`, and `host` entities |
| `NetworkPolicy` | `allow-dns-egress` | Allow DNS (UDP/TCP 53) and internet egress, except the IMDS endpoint (169.254.169.254/32) |
| `CiliumNetworkPolicy` | `allow-pod-identity-egress` | Permit egress to the EKS Pod Identity agent (`host` entity, `169.254.170.23:80`) so pods can fetch their workload AWS credentials (ADR-041) |
| Namespace PSA labels | `enforce=baseline`, `warn`/`audit=restricted` | Block privileged/hostPath/hostNetwork pods (node-escape vectors) |
| `RoleBinding` | `tenant-developers` | Bind group `team-<name>:developers` to the `tenant-developer` ClusterRole (ADR-039) |

Pods are isolated by namespace. Cilium enforces NetworkPolicies at the eBPF
level -- there is no iptables fallback. Cross-namespace traffic is blocked
unless an explicit policy allows it.

Gateway routing works because the `preprod-gateway` listener sets
`allowedRoutes.namespaces.from: All`. Any namespace can create an HTTPRoute
referencing the gateway.

Two policies work together to allow gateway traffic:

- The **`allow-gateway-ingress`** Kubernetes NetworkPolicy permits ingress
  from pods in the gateway namespace (`default`) and `kube-system`.
- The **`allow-gateway-envoy`** CiliumNetworkPolicy permits ingress from
  the `ingress`, `remote-node`, and `host` Cilium entities. This is
  required because Cilium's Gateway API Envoy proxy uses the reserved
  `ingress` identity (identity 8) for upstream connections — not the `host`
  identity, despite running with `hostNetwork`. Standard Kubernetes
  NetworkPolicy `ipBlock` CIDR rules cannot match Cilium identities.

## vCluster Mode (Deferred)

> **Status:** Deferred per ADR-033. The information below describes the design
> intent; vCluster mode is not currently deployed.

The tenant module supports a `mode = "vcluster"` option that delegates to
`infra/modules/vcluster/` (chart version 0.34.1). When active, it creates:

1. Host namespace `vc-<name>`.
2. A vCluster Helm release with virtual API server, etcd, and syncer.
3. Policy enforcement (resource quotas, limit ranges, network policies).

**Why it's deferred:** The open-source vCluster chart does not support
`sync.toHost.customResources` — this is a Pro/Free tier feature requiring the
vCluster Platform operator and a connection to `admin.loft.sh`. Without
HTTPRoute sync, apps inside a vCluster cannot register with the host cluster's
Gateway API Gateway and are unreachable from the internet.

## Network Topology

### Namespace mode policies

The Composition provisions three Kubernetes NetworkPolicies and two
CiliumNetworkPolicies per namespace:

**default-deny-ingress** -- Matches all pods, blocks all ingress. This is the
baseline; everything is denied unless another policy explicitly allows it.

```yaml
spec:
  podSelector: {}          # all pods
  policyTypes: [Ingress]
  # no ingress rules = deny all
```

**allow-gateway-ingress** -- Permits ingress from the gateway namespace
and kube-system so infrastructure components can reach tenant pods.

```yaml
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: default       # gateway namespace
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
```

**allow-gateway-envoy** (CiliumNetworkPolicy) -- Permits ingress from
Cilium's `ingress`, `remote-node`, and `host` entities. This is required
because the Gateway API Envoy proxy uses the reserved `ingress` identity
(identity 8) for upstream connections, which standard Kubernetes
NetworkPolicy cannot match.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-gateway-envoy
spec:
  endpointSelector: {}
  ingress:
  - fromEntities:
    - ingress
    - remote-node
    - host
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

**allow-pod-identity-egress** (CiliumNetworkPolicy) -- Permits egress to the EKS
Pod Identity agent so tenant pods can fetch their workload AWS credentials
(ADR-041). The agent serves credentials at the link-local `169.254.170.23:80`,
which Cilium classifies as the `host` entity — a CIDR `toCIDR` rule cannot match it,
so this needs `toEntities: [host]`. (IMDS at `169.254.169.254` is also `host` and thus
reachable, but the node enforces IMDSv2 with `HttpPutResponseHopLimit=1`, so a pod —
one hop from the node — still cannot steal the node role.)

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-pod-identity-egress
spec:
  endpointSelector: {}
  egress:
  - toEntities: [host]
    toPorts: [{ports: [{port: "80", protocol: TCP}]}]
```

### vCluster mode policies (deferred)

When vCluster mode is active, vCluster's built-in policy enforcement creates
its own set of NetworkPolicies, LimitRanges, and ResourceQuotas in the host
namespace (`vc-<name>`). The platform does not layer additional custom policies
on top. See ADR-033 for why vCluster mode is currently deferred.

## Resource Governance

### Defaults

| Resource | Default |
|----------|---------|
| `requests.cpu` / `limits.cpu` | 4 cores |
| `requests.memory` / `limits.memory` | 8Gi |
| `pods` | 20 |
| `services` | 20 |
| `services.loadbalancers` | 0 (ingress via the shared Gateway, ADR-017 — no per-tenant NLBs) |
| `persistentvolumeclaims` | 10 |
| `requests.storage` | 50Gi |
| Container default limit | 500m CPU, 512Mi memory |
| Container default request | 100m CPU, 128Mi memory |

### Per-team overrides

A team's `XTenant` claim accepts a per-team `resourceQuota` override (set in the
team's `gitops/tenant-claims/<env>/<team>.yaml`); omitting it uses the defaults above:

```yaml
spec:
  resourceQuota:
    cpu:    "8"
    memory: "16Gi"
    pods:   40
```

Resource quotas apply at the team level (namespace-scoped), not per-app. All
apps within a team share the same quota.

For vCluster tenants (when enabled), resource limits are managed by vCluster's
built-in policy enforcement settings. See ADR-033 for current status.

## Sources of Truth: the `XTenant` claim and `teams.hcl`

The **`XTenant` claim is the tenant source of truth** — it provisions the
namespace, RBAC, quotas, NetworkPolicies, per-team Kyverno guardrails, the
`Pod-team-<team>` role + Pod Identity association, the `DeveloperAccess-<team>`
role + EKS access entry, and cross-account ECR. The Composition provisions all
of it from that one CR. See [Crossplane Tenant API](crossplane-tenant-api.md).

`teams.hcl` is **no longer** the tenant-provisioning source of truth. It now
feeds only two **non-provisioning** concerns:

```text
+---------------------------+        +---------------------------+
| gitops/tenant-claims/     |        |  teams.hcl                |
|  XTenant per team (YAML)   |        |  alpha (migrated=true)    |
|  alpha, bravo              |        |  bravo  (migrated=true)   |
+-----------+---------------+         +-----------+---------------+
            |                                     |
            | ArgoCD sync (tenant-claims-preprod) | read_terragrunt_config()
            v                                     |
   Crossplane Composition               +---------+---------+
   ──────────────────────               |                   |
   Namespace, RBAC, quota,              v                   v
   NetworkPolicies, Kyverno          argocd-apps/        policy/
   restrict-*, Pod Identity,         terragrunt.hcl      terragrunt.hcl
   DeveloperAccess + access            |                   |
   entry, ECR repos                    v                   v
                                    ArgoCD Application   verify-images /
                                    per app + preview    verify-attestations
                                    ApplicationSets      (verify_subjects)
```

**EKS access entries** are now provisioned by the **Composition** (not `eks/`):
each team's `DeveloperAccess-<team>` role gets a group-mapped access entry tying
it to the Kubernetes group `team-<team>:developers`. Authorization is the
namespace-scoped `tenant-developers` RoleBinding the Composition provisions (not
an AWS-managed policy). See ADR-039. The per-team role/access-entry loops were
removed from the `eks`/`iam-roles` units.

- All teams: principal `DeveloperAccess-<name>` → group `team-<name>:developers`

**ArgoCD apps** (platform cluster, from `teams.hcl`): ArgoCD on the platform
cluster creates Application resources targeting the preprod cluster. Each app's
`repo_url` and `repo_path` from `teams.hcl` define the GitOps source; the
destination namespace is derived from the team name. Apps with `preview = true`
get an additional ApplicationSet that creates ephemeral Applications for open
pull requests (ADR-032). Migrated teams carry `migrated = true`, which withdraws
them from the (now-removed) Terragrunt infra loops and tells the `policy` unit to
skip the per-team `restrict-*` guardrails (the Composition owns those).

**Supply-chain policies** (`policy/`, from `teams.hcl`): the platform-owned
`verify-images-team-<team>` / `verify-attestations-team-<team>` policies read
each team's repo→identity mapping. These stay platform-owned for **all** teams
(including migrated ones) — a tenant must not own its own signature trust root,
so they are deliberately not part of the claim/Composition.

### Adding a new team

Onboarding a team is now an `XTenant` claim YAML in `gitops/tenant-claims/<env>/`
(synced by ArgoCD), plus the `teams.hcl` entry for app delivery + supply-chain
policies. Follow the
[tenant onboarding runbook](../runbooks/tenant-onboarding.md) — it walks the claim
fields, the `migrated = true` flag, and verification. A minimal claim example
lives at `infra/modules/crossplane/examples/tenant-gamma.yaml`.

## Tenant AWS Access (Pod Identity)

Tenants reach AWS resources via **platform-managed EKS Pod Identity** (ADR-041/047), not IRSA. A team
declares its needs in its **`XTenant` claim** (`aws.serviceAccount` + `aws.policyStatements`); the
Composition provisions a `Pod-team-<team>` role (trust `pods.eks.amazonaws.com` + an `aws:SourceAccount`
condition, with a deny-escalation permissions boundary), its RolePolicy from the claim's
`policyStatements`, and a `PodIdentityAssociation` binding `(cluster, team-<team>, <serviceAccount>) →
role`. Pods running as that named SA receive credentials from the Pod Identity agent — no
`eks.amazonaws.com/role-arn` annotation (which stays denied as a backstop).

**Generic AWS access, not S3 buckets.** Access to arbitrary AWS is via the claim's generic
`aws.policyStatements` (IAM statements granted to the `Pod-team-<team>` role, capped by the
deny-escalation boundary). The earlier per-team S3 buckets were a **demo** of the cross-account pattern
and are **not** provisioned — there is no S3-shared unit.

**Isolation is default-deny, by construction.** A team's `Pod-team-<team>` role is named from the team
key and grants only what its own claim declares; the deny-escalation boundary prevents privilege growth.
Tenants cannot create Pod Identity associations or `XTenant` claims (the S1 `restrict-tenant-control-plane`
backstop denies tenant principals), and the egress NetworkPolicy blocks IMDS so they cannot steal the
node role. See the runbook
[`tenant-aws-access-pod-identity.md`](../runbooks/tenant-aws-access-pod-identity.md) and the
[Crossplane Tenant API](crossplane-tenant-api.md).

## PR Preview Environments

Apps with `preview = true` in `teams.hcl` get ephemeral preview deployments
for open pull requests. See [ADR-032](../adrs/032-pr-preview-environments.md)
for full design details.

```text
Developer opens PR
  -> GitHub Actions builds image (team-<team>/<app>:<head-sha>)
  -> ArgoCD ApplicationSet (PR generator) detects open PR
  -> Creates ephemeral Application with kustomize overrides:
     - namePrefix: pr-<N>-
     - commonLabels: app.kubernetes.io/instance = pr-<N>
     - images: ECR image with head SHA tag
     - patches: HTTPRoute hostname rewrite
     - nameReference: backendRef auto-update via app repo config
  -> Preview at <app>-pr-<N>.preprod.aws.refplat.org
  -> PR closes -> ArgoCD auto-deletes preview resources
```

Label selector isolation via `commonLabels` prevents traffic routing
collisions between stable and preview deployments. The stable Application
uses `app.kubernetes.io/instance: stable`; each preview uses
`app.kubernetes.io/instance: pr-<N>`.

## Security Boundaries

### What namespace mode protects against

- **Cross-tenant network traffic** -- Default-deny ingress with Cilium
  enforcement. Pods in `team-alpha` cannot receive traffic from `team-bravo`.
- **Resource exhaustion** -- ResourceQuota caps CPU, memory, and pod count.
  LimitRange sets defaults so pods without explicit requests still get bounded.
- **Unauthorized API access** -- each team's `DeveloperAccess-<team>` role is
  group-mapped and bound (namespace-scoped) to the `tenant-developer` role in its
  own namespace only. A developer can edit only their own namespace and can assume
  only their own team's role (ADR-039).
- **Node escape via pods** -- Pod Security Admission (`enforce=baseline`) blocks
  privileged, hostPath, and host-network/PID pods; the egress policy blocks the IMDS
  endpoint so pods cannot steal node-role credentials.

### What namespace mode does NOT protect against

- **Kernel-level exploits** -- Namespaces share the host kernel. A container escape
  via a kernel/runtime vulnerability (i.e. not the pod-spec vectors PSA blocks)
  grants access to the node and all co-located tenants.
- **Noisy-neighbor I/O** -- ResourceQuota does not cap disk or network I/O.
  A pod performing heavy disk writes can degrade node performance.
- **CRD visibility** -- Cluster-scoped resources (CRDs, ClusterRoles, Nodes)
  are visible to anyone with list permissions at the cluster scope.

### What vCluster mode would add (deferred — ADR-033)

- **Full API server isolation** -- Each tenant gets a virtual API server. CRDs,
  RBAC, namespaces, and admission webhooks are scoped to the virtual cluster.
- **Stronger blast radius** -- A misconfigured admission webhook or runaway
  controller only impacts the virtual cluster, not the host.
- **Independent RBAC** -- Tenants can create ClusterRoles and
  ClusterRoleBindings inside their virtual cluster without host-level impact.
- **Limitation** -- HTTPRoute sync requires vCluster Pro/Free tier. Without it,
  apps inside a vCluster are not publicly accessible via the shared Gateway.
