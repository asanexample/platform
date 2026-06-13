# Preprod Environment Isolation Model

> Related: [ADR-027 — Hybrid Environment Isolation](../adrs/027-hybrid-tenant-isolation-model.md),
> [ADR-033 — Defer vCluster Support](../adrs/033-defer-vcluster-tenant-support.md),
> [ADR-041 — Pod Identity for Environment Workloads](../adrs/041-pod-identity-for-tenant-workloads.md),
> [ADR-046 — BACK stack for developer self-service](../adrs/046-back-stack-for-developer-self-service.md),
> [ADR-047 — Pod Identity standard](../adrs/047-pod-identity-as-aws-identity-standard.md),
> [ADR-067 — IDP domain model (Team / Product / Service / Environment)](../adrs/067-idp-domain-model.md)

<!-- -->

> **Domain model is Team → Product → Service → Environment (ADR-067).** An **Environment** —
> a Product at a Stage [for a Customer] — is the provisioned unit on the cluster (the unit this
> doc describes). Ownership is the git-native **`Team`** CR (an isolation/quota envelope), and a
> Team's **Products** group the deployable systems; the namespace `<team>-<product>-<stage>` is
> the deployment unit, NOT a degenerate `team == environment` namespace. The matured
> scale/compliance/multi-cloud dimensions — a compliance-driven isolation spectrum up to dedicated
> cluster/account, cloud-neutral placement with data residency — ride on the same
> [ADR-067](../adrs/067-idp-domain-model.md) `Environment` (`tier`, `isolation.compute`, `residency`).
> Everything below describes how preprod runs **today** on this model.

<!-- -->

> **Provisioning is Crossplane.** This document describes the environment
> *isolation model* — what an environment looks like on the cluster (namespace mode,
> NetworkPolicies, RBAC, quotas, Pod Identity). What provisions it is a single
> declarative **`XEnvironment` claim** (`platform.refplat.org/v1beta1`) reconciled by a
> Crossplane **Environment Composition** (`environment-v3`). Both demo Environments
> (alpha/demo, bravo/demo) are live on it. The v2-era Terragrunt path — the
> `infra/modules/environment` module and the `environments`/`pod-identity` units — was
> **retired and deleted** at the cutover. For the claim API (XRD schema, Composition
> pipeline, claim lifecycle, federated topology) see
> [Crossplane Environment API](crossplane-environment-api.md). Where this doc says "the
> Composition provisions …", read it as the `environment-v3` Composition rendering per
> `XEnvironment` — the resulting cluster footprint is described below.

## Overview

The preprod EKS cluster (`preprod-use1-eks`, account `<PREPROD_ACCOUNT_ID>`) uses
**namespace-based environment isolation** on a shared cluster. Each Environment gets a
dedicated namespace with ResourceQuotas, LimitRanges, and Cilium NetworkPolicies.

Each Environment is one **`XEnvironment` claim**; the Crossplane Environment Composition
reconciles it into the namespace, RBAC, quotas, NetworkPolicies, per-product Kyverno
guardrails, per-service Pod Identity, and cross-account ECR. ArgoCD syncs the claim YAMLs
from `gitops/environments/<team>/<product>/`. See
[Crossplane Environment API](crossplane-environment-api.md).

> **Note:** The environment module also supports a vCluster mode for stronger isolation
> (CRD independence, virtual control plane), but this is **deferred** (ADR-033).
> The open-source vCluster chart cannot sync HTTPRoute resources to the host
> cluster's Gateway, making vCluster environments unreachable from the internet.
> All teams currently use namespace mode.

## Architecture Diagram

### Namespace mode (alpha-demo-dev)

```text
Internet
  |
  v
+------------------+
|   AWS NLB        |  (created by Cilium GatewayClass)
+------------------+
  |
  v
+--------------------------------------------------+
| Gateway: preprod-gateway  (ns: default)          |
| GatewayClass: cilium                             |
| Listeners: HTTPS :443, HTTP :80                  |
| allowedRoutes.namespaces.from: All               |
+--------------------------------------------------+
  |
  v
+--------------------------------------------------+
| HTTPRoute         (ns: alpha-demo-dev)           |
| parentRef: preprod-gateway/default               |
| hostname: demo-alpha-dev.preprod.aws.refplat.org |
+--------------------------------------------------+
  |
  v
+--------------------------------------------------+
| Service           (ns: alpha-demo-dev)           |
+--------------------------------------------------+
  |
  v
+--------------------------------------------------+
| Pod               (ns: alpha-demo-dev)           |
| NetworkPolicy: default-deny-ingress              |
|                + allow-gateway-ingress           |
|                + allow-dns-egress                |
| CiliumNetworkPolicy: allow-gateway-envoy         |
+--------------------------------------------------+
```

### Namespace mode (bravo-demo-dev)

Same architecture as alpha-demo-dev. Both Environments use namespace isolation.

> **vCluster mode** is supported by the environment module but currently deferred
> (ADR-033) because HTTPRoute sync from virtual to host cluster requires the
> vCluster Platform operator (not available in the open-source chart).

## Namespace Mode Detail

The Crossplane Environment Composition provisions these resources for each Environment (the
retired v2 `environment` module created the same set for `mode = "namespace"`):

| Resource | Name | Purpose |
|----------|------|---------|
| `Namespace` | `<team>-<product>-<stage>` | Workload boundary |
| `ResourceQuota` | `environment-quota` | CPU, memory, pod, service/LB, PVC, and storage caps |
| `LimitRange` | `environment-limits` | Default container requests/limits |
| `NetworkPolicy` | `default-deny-ingress` | Block all inbound traffic by default |
| `NetworkPolicy` | `allow-gateway-ingress` | Permit traffic from the Gateway and kube-system namespaces |
| `CiliumNetworkPolicy` | `allow-gateway-envoy` | Permit traffic from Cilium `ingress`, `remote-node`, and `host` entities |
| `NetworkPolicy` | `allow-dns-egress` | Allow DNS (UDP/TCP 53) and internet egress, except the IMDS endpoint (169.254.169.254/32) |
| `CiliumNetworkPolicy` | `allow-pod-identity-egress` | Permit egress to the EKS Pod Identity agent (`host` entity, `169.254.170.23:80`) so pods can fetch their workload AWS credentials (ADR-041) |
| Namespace PSA labels | `enforce=baseline`, `warn`/`audit=restricted` | Block privileged/hostPath/hostNetwork pods (node-escape vectors) |
| `RoleBinding` | `environment-developers` | Bind group `<team>-<product>-<stage>:developers` to the `environment-developer` ClusterRole (ADR-039) |

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

The environment module supports a `mode = "vcluster"` option that delegates to
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
and kube-system so infrastructure components can reach environment pods.

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
Pod Identity agent so environment pods can fetch their workload AWS credentials
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
| `services.loadbalancers` | 0 (ingress via the shared Gateway, ADR-017 — no per-environment NLBs) |
| `persistentvolumeclaims` | 10 |
| `requests.storage` | 50Gi |
| Container default limit | 500m CPU, 512Mi memory |
| Container default request | 100m CPU, 128Mi memory |

### Per-environment overrides

An `XEnvironment` claim accepts a per-environment `quota` override (set in the
claim's `gitops/environments/<team>/<product>/<stage>[-<customer>].yaml`); omitting it uses
the defaults above. The override is bounded by the owning Team's envelope `quotaCap`:

```yaml
spec:
  quota:
    cpu:    "8"
    memory: "16Gi"
    pods:   40
```

Resource quotas apply at the Environment level (namespace-scoped), not per-service. All
services within an Environment share the same quota.

For vCluster environments (when enabled), resource limits are managed by vCluster's
built-in policy enforcement settings. See ADR-033 for current status.

## Sources of Truth: the `XEnvironment` claim and the git-native registries

The **`XEnvironment` claim is the environment source of truth** — it provisions the
namespace, RBAC, quotas, NetworkPolicies, per-product Kyverno guardrails, the per-service
`Pod-<team>-<product>-[<customer>-]<stage>-<svc>` role + Pod Identity association, the
`DeveloperAccess-<team>` role + EKS access entry, and cross-account ECR. The Composition
provisions all of it from that one CR. See
[Crossplane Environment API](crossplane-environment-api.md).

The v2 `teams.hcl` app-delivery registry is **retired**. Team identity is the git-native
**`Team`** CR (`gitops/teams/<team>.yaml`, ADR-063) and the deployable systems are
**`Product`** CRs (`gitops/products/<team>/<product>.yaml`); app delivery and supply-chain
policy now **derive** from the `XEnvironment`/`Product` registries:

```text
+-----------------------------+      +-----------------------------+
| gitops/environments/        |      |  gitops/products/<team>/    |
|  XEnvironment per env (YAML) |      |   Product per system (YAML) |
|  alpha/demo/dev, bravo/...   |      |   alpha/demo, bravo/demo    |
+-----------+-----------------+       +-----------+-----------------+
            |                                     |
            | ArgoCD sync (per-product AppSet)    | fileset + yamldecode
            v                                     |
   Crossplane Composition               +---------+---------+
   ──────────────────────               |                   |
   Namespace, RBAC, quota,              v                   v
   NetworkPolicies, Kyverno          argocd-apps/        policy/
   restrict-*, Pod Identity,         (v3-delivery)       terragrunt.hcl
   DeveloperAccess + access            |                   |
   entry, ECR repos                    v                   v
                                    ArgoCD Application   verify-images /
                                    per Environment      verify-attestations
                                    + preview            (verify_subjects)
```

**EKS access entries** are provisioned by the **Composition** (not `eks/`):
each team's `DeveloperAccess-<team>` role gets a group-mapped access entry tying
it to the per-namespace Kubernetes group `<team>-<product>-<stage>:developers`.
Authorization is the namespace-scoped `environment-developers` RoleBinding the
Composition provisions (not an AWS-managed policy). See ADR-039. The per-team
role/access-entry loops were removed from the `eks`/`iam-roles` units.

- All teams: principal `DeveloperAccess-<team>` → group `<team>-<product>-<stage>:developers`

**ArgoCD apps** (platform cluster, ADR-069): `argocd-apps` runs **one
ApplicationSet per Product**, a git-files generator over
`gitops/environments/<team>/<product>/*.yaml` that emits one Application per
`XEnvironment` targeting the preprod cluster. The GitOps source is the Product's
app repo (`spec.repo`); the Application syncs `k8s/overlays/<stage>`, with the
destination namespace + generated host injected. Services with `preview: true`
get an additional ApplicationSet that creates ephemeral Applications for open
pull requests (ADR-032).

**Supply-chain policies** (`policy/`, derived from the `Product`/`XEnvironment`
registries): the platform-owned `verify-images-<product>` /
`verify-attestations-<product>` policies read each product's repo→identity
mapping. These stay platform-owned for **all** products — an environment must not
own its own signature trust root, so they are deliberately not part of the
claim/Composition.

### Adding a new environment

Onboarding an environment is now an `XEnvironment` claim YAML in
`gitops/environments/<team>/<product>/` (synced by ArgoCD), under an owning
`Team` CR and `Product` CR. Follow the
[environment onboarding runbook](../runbooks/environment-onboarding.md) — it walks the claim
fields (`team`/`product`/`stage`/`tier`/`services`) and verification. A minimal
claim example lives at `infra/modules/crossplane/examples/environment-gamma.yaml`.

## Environment AWS Access (Pod Identity)

Environments reach AWS resources via **platform-managed EKS Pod Identity** (ADR-041/047), not IRSA. An
Environment declares each service's needs in its **`XEnvironment` claim**
(`services.<svc>.permissions.aws` — `serviceAccount` + `policyStatements`); the Composition provisions, per
service, a `Pod-<team>-<product>-[<customer>-]<stage>-<svc>` role (trust `pods.eks.amazonaws.com` + an
`aws:SourceAccount` condition, with a deny-escalation permissions boundary), its RolePolicy from the claim's
`policyStatements`, and a `PodIdentityAssociation` binding `(cluster, <ns>, <serviceAccount>) → role`. Pods
running as that named SA receive credentials from the Pod Identity agent — no `eks.amazonaws.com/role-arn`
annotation (which stays denied as a backstop).

**Generic AWS access, not S3 buckets.** Access to arbitrary AWS is via the claim's generic per-service
`policyStatements` (IAM statements granted to the service's `Pod-…` role, capped by the
deny-escalation boundary). The earlier per-team S3 buckets were a **demo** of the cross-account pattern
and are **not** provisioned — there is no S3-shared unit.

**Isolation is default-deny, by construction.** A service's `Pod-…` role is named from the
team/product/stage/service and grants only what its own claim declares; the deny-escalation boundary prevents
privilege growth. Environments cannot create Pod Identity associations or `XEnvironment` claims (the S1
`restrict-environment-control-plane` backstop denies environment principals), and the egress NetworkPolicy
blocks IMDS so they cannot steal the node role. See the runbook
[`environment-aws-access-pod-identity.md`](../runbooks/environment-aws-access-pod-identity.md) and the
[Crossplane Environment API](crossplane-environment-api.md).

## PR Preview Environments

Services with `preview: true` on their `XEnvironment` claim get ephemeral preview
deployments for open pull requests. See [ADR-032](../adrs/032-pr-preview-environments.md)
for full design details.

```text
Developer opens PR
  -> GitHub Actions builds image (team-<team>/<product>-<svc>:<head-sha>)
  -> ArgoCD ApplicationSet (PR generator) detects open PR
  -> Creates ephemeral Application with kustomize overrides:
     - namePrefix: pr-<N>-
     - commonLabels: app.kubernetes.io/instance = pr-<N>
     - images: ECR image with head SHA tag
     - patches: HTTPRoute hostname rewrite
     - nameReference: backendRef auto-update via app repo config
  -> Preview at <product>-<team>-<stage>-pr-<N>.preprod.aws.refplat.org
  -> PR closes -> ArgoCD auto-deletes preview resources
```

Label selector isolation via `commonLabels` prevents traffic routing
collisions between stable and preview deployments. The stable Application
uses `app.kubernetes.io/instance: stable`; each preview uses
`app.kubernetes.io/instance: pr-<N>`.

## Security Boundaries

### What namespace mode protects against

- **Cross-environment network traffic** -- Default-deny ingress with Cilium
  enforcement. Pods in `alpha-demo-dev` cannot receive traffic from `bravo-demo-dev`.
- **Resource exhaustion** -- ResourceQuota caps CPU, memory, and pod count.
  LimitRange sets defaults so pods without explicit requests still get bounded.
- **Unauthorized API access** -- each team's `DeveloperAccess-<team>` role is
  group-mapped and bound (namespace-scoped) to the `environment-developer` role in each
  of its Environments' namespaces only. A developer can edit only their own team's
  Environment namespaces and can assume only their own team's role (ADR-039).
- **Node escape via pods** -- Pod Security Admission (`enforce=baseline`) blocks
  privileged, hostPath, and host-network/PID pods; the egress policy blocks the IMDS
  endpoint so pods cannot steal node-role credentials.

### What namespace mode does NOT protect against

- **Kernel-level exploits** -- Namespaces share the host kernel. A container escape
  via a kernel/runtime vulnerability (i.e. not the pod-spec vectors PSA blocks)
  grants access to the node and all co-located environments.
- **Noisy-neighbor I/O** -- ResourceQuota does not cap disk or network I/O.
  A pod performing heavy disk writes can degrade node performance.
- **CRD visibility** -- Cluster-scoped resources (CRDs, ClusterRoles, Nodes)
  are visible to anyone with list permissions at the cluster scope.

### What vCluster mode would add (deferred — ADR-033)

- **Full API server isolation** -- Each environment gets a virtual API server. CRDs,
  RBAC, namespaces, and admission webhooks are scoped to the virtual cluster.
- **Stronger blast radius** -- A misconfigured admission webhook or runaway
  controller only impacts the virtual cluster, not the host.
- **Independent RBAC** -- Environments can create ClusterRoles and
  ClusterRoleBindings inside their virtual cluster without host-level impact.
- **Limitation** -- HTTPRoute sync requires vCluster Pro/Free tier. Without it,
  apps inside a vCluster are not publicly accessible via the shared Gateway.
