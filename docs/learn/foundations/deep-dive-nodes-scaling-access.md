# Learn: Foundations — nodes, scaling & access (deep dive)

Four pieces make up this layer: a fixed **system** node group as the floor, elastic **Karpenter**
on top, a **descheduler** that rebalances what lands unevenly, and **Tailscale** as the staff door
into a private-only cluster. This dive opens each box and shows the machinery — why it's shaped this
way and the exact places it bites. It's for a platform engineer who wants to operate this layer, not
just picture it.

Two metaphors run throughout. The system group is an **always-on generator** — the lights that can
never go out. Karpenter is **renting generators by the hour** — right-sized capacity, just-in-time,
returned when quiet. Almost every design choice below is one of those two defending its job.

---

## Part A — the compute floor: why one node group can never be Karpenter's

Start with the thing that must exist before anything else can run: the **system** managed node group.
On the platform (hub) cluster it is, verified live:

```console
$ kubectl --context platform get nodes -L node-role,karpenter.sh/nodepool,node.kubernetes.io/instance-type
NAME                          STATUS   ROLES    AGE   VERSION   NODE-ROLE   NODEPOOL   INSTANCE-TYPE
ip-10-100-2-20.ec2.internal   Ready    <none>   98m   v1.35.6   system                 t4g.xlarge
ip-10-100-2-28.ec2.internal   Ready    <none>   92m   v1.35.6               default    r6g.medium
ip-10-100-2-38.ec2.internal   Ready    <none>   98m   v1.35.6   system                 t4g.xlarge
```

Two `t4g.xlarge` nodes labelled `node-role=system`, and one `r6g.medium` with no role but a
`karpenter.sh/nodepool=default` label — that third one is a rented generator, and we'll get to it in
Part B. The two system nodes are the always-on floor.

The system group is defined in
[`node-groups/terragrunt.hcl`](https://github.com/asanexample/platform/blob/main/infra/live/aws/platform/us-east-1/platform/node-groups/terragrunt.hcl):
a single `t4g.xlarge` instance type (4 vCPU / 16 GiB, **Graviton** arm64), `desired_size = 2`,
`max_size = 3`, `min_size = 2`. Preprod's floor is smaller — one `t4g.large` (2 vCPU / 8 GiB) — because
it carries no observability backends, Keycloak, or Backstage.

### Why the floor can't be Karpenter

The constraint is almost tautological once you see it: **Karpenter can't provision the node it runs
on.** Karpenter is a controller — a pod — and a pod needs a node. If the only nodes were
Karpenter-provisioned, a cold cluster (or one where every node just got consolidated away) would have
no Karpenter running, and therefore nothing to bring a node back. It's the generator that starts the
other generators: it can't be one of the ones it starts.

So a small fixed group stays, and it's deliberately the home for everything that is cluster-critical
and un-provisionable-by-Karpenter:

- **Karpenter itself** — pinned there by `nodeSelector: { node-role: system }` in the Helm values, so
  consolidation can never kill its own controller.
- **CoreDNS and the Cilium operator** — the cluster's own nervous system.
- The **heavy standing JVM/stateful stack** — Keycloak, ArgoCD, Crossplane, the Prometheus/Mimir/Loki/
  Tempo/Pyroscope backends, Backstage.
- **Node-pinned DaemonSet pods** that simply cannot be served by an elastic node — a DaemonSet runs one
  pod per node, so it has nowhere to scale up to.

That last category is why the platform system node grew from `t4g.large` to `t4g.xlarge`. The comment in
the unit is blunt about it: the per-node DaemonSet slab (Cilium, Beyla, Alloy, node-exporter, otel) plus
the standing load saturated the old 2-vCPU node at ~100% CPU — the `alloy-profiles` DaemonSet pod couldn't
even fit. The xlarge buys per-node headroom; Karpenter handles bursts above this floor, never the floor
itself.

### The ForceNew trap — a routine-looking apply that briefly severs the cluster

That `t4g.large → t4g.xlarge` change hides the nastiest gotcha in this layer, and
[ADR-078](../../adrs/078-cluster-elasticity-karpenter.md) records it as an as-built scar. Changing a
managed node group's `instance_types` is a **ForceNew** attribute in the AWS provider — OpenTofu can't
mutate it in place, so it destroys the node group and creates a new one. The module's
`create_before_destroy` sits only on the launch template, not the group (the group name is fixed), so
for ~3 minutes the cluster runs on replacement nodes coming up while the old ones drain.

It bites harder here than on a normal cluster because the in-cluster Tailscale subnet router gets evicted
during that window — and the subnet router is how you reach the private EKS API (Part D). So a one-line
instance-type edit, which reads like a trivial resize, briefly makes the private API server unreachable
from your laptop. The lesson the ADR draws: an `instance_types` change is a deliberate, monitored step,
planned like a small maintenance, not slipped into a routine apply.

### Node hardening — three things baked into the launch template

The system group ships a custom
[launch template](https://github.com/asanexample/platform/blob/main/infra/modules/aws/eks-node-group/main.tf)
built for hardening. Three details worth knowing:

1. **IMDSv2, hop limit 1.** `http_tokens = "required"` (session-token-only metadata) and
   `http_put_response_hop_limit = 1`. The hop limit is the sharp one: metadata requests get one network
   hop, so a pod (one hop from the node) can't reach the [instance metadata
   service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)
   and steal the node's IAM-role credentials. Pods get their own identity via
   [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html), not the node's.
2. **Encrypted root EBS — or the launch is refused.** The template sets `encrypted = true` on a 20 GiB
   gp3 root volume. This isn't belt-and-suspenders: the org's `enforce-encryption` SCP
   (`DenyUnencryptedEbsOnLaunch`) blocks the instance launch entirely if the volume is unencrypted — you'd
   see `not authorized to launch instances with this launch template`. The encryption isn't a hardening
   nicety; it's the price of admission, enforced from above the account.
3. **`maxPods: 110`.** AL2023 defaults kubelet's max-pods to the instance's ENI IP capacity (~35 on this
   size) — which makes sense on the default VPC-CNI, where every pod burns an ENI IP. But under Cilium's
   overlay (`cluster-pool`) pods don't consume ENI IPs, so that cap is artificial. A small
   `NodeConfig` MIME fragment in the launch template lifts it to the Kubernetes default of 110, so density
   is bound by CPU/memory, not IP addresses.

---

## Part B — Karpenter: renting the right generator, and returning it

The elastic layer. When pods go `Pending`, [Karpenter](https://karpenter.sh/) reads exactly what
they need — CPU, memory, architecture, zone — and launches the cheapest EC2 instance that fits,
**bin-packing** multiple pending pods onto one node where it can. When a node goes empty, it
**consolidates** — terminates it. That live `r6g.medium` from Part A is one such node; its `NodeClaim`
is Karpenter's record of the rental:

```console
$ kubectl --context platform get nodeclaims
NAME            TYPE         CAPACITY    ZONE         NODE                          READY   AGE
default-vtbn6   r6g.medium   on-demand   us-east-1c   ip-10-100-2-28.ec2.internal   True    92m
```

Karpenter picked `r6g.medium` — not a type anyone hard-coded. That's the whole point of D1 in
[ADR-078](../../adrs/078-cluster-elasticity-karpenter.md).

### Why Karpenter, not Cluster Autoscaler

Cluster Autoscaler is ASG-bound: it scales pre-defined Auto Scaling Groups, so you need one group per
instance shape you want, it reacts slowly (it edits a `desired` count and waits for the ASG), and it
never bin-packs or consolidates — it only adds and removes whole groups. Karpenter is instance-flexible:
its `NodePool` expresses requirements (arch, families, capacity type, a memory floor), not a fixed shape,
and it picks the cheapest sufficient instance per request in seconds. On a cost-tight, park-when-idle
reference cluster, **consolidation is the decisive feature** — it's the "return the generator when it's
quiet" half of the metaphor, and Cluster Autoscaler simply doesn't have it.

### The NodePool, and the two consolidation personalities

The single `NodePool` (name `default`) is rendered from a
[local Helm chart](https://github.com/asanexample/platform/blob/main/infra/modules/aws/karpenter/charts/nodepool/templates/nodepool.yaml).
Its requirements: `kubernetes.io/arch: arm64` (Graviton-first), a default family set of
`t4g/m6g/m7g/c6g/r6g`, and a per-cluster capacity-type + consolidation policy. That split is the
interesting part — the same module, two personalities:

| | platform (hub) | preprod (spoke) |
|---|---|---|
| capacity types | `on-demand` | `spot`, `on-demand` |
| `consolidationPolicy` | `WhenEmpty` | `WhenEmptyOrUnderutilized` |
| CPU / memory ceiling | 32 vCPU / 128 GiB | 48 vCPU / 192 GiB |

`WhenEmpty` (platform) only reclaims fully-empty nodes — it never disrupts a running pod. That's the
right call on the stateful hub, where the TSDBs, Keycloak, and CNPG databases must not be shuffled;
paired with `karpenter.sh/do-not-disrupt` + PodDisruptionBudgets on those workloads, a Karpenter node is
never yanked out from under state. `WhenEmptyOrUnderutilized` (preprod) is aggressive: it actively repacks
underutilized nodes onto fewer nodes to save money, accepting the churn because preprod's tenant
workloads are ephemeral and reschedule freely. Both use `consolidateAfter: 1m` to damp flapping, and a
hard `limits` ceiling so Karpenter can never runaway-provision past the cost guardrail.

### Three details that keep Karpenter honest

**Auth is Pod Identity, not IRSA.** The controller's IAM role trusts `pods.eks.amazonaws.com` (ADR-047),
and the `karpenter` ServiceAccount carries no IRSA annotation — the Helm values explicitly set
`annotations: {}`. This is the platform-wide move away from IRSA for platform add-ons.

**The Cilium-first startup taint.** Every Karpenter node is born with a taint, verified live on the
NodePool:

```console
$ kubectl --context platform get nodepool default -o jsonpath='{.spec.template.spec.startupTaints}'
[{"effect":"NoSchedule","key":"node.cilium.io/agent-not-ready"}]
```

This is the "wet paint" sign, expressed for nodes that appear at 3 a.m. Because the cluster
is BYOCNI ([Cilium](https://cilium.io/) installed before nodes are Ready), a fresh node has no
networking until Cilium's agent DaemonSet lands on it. The taint repels application pods until Cilium
comes up and removes the taint itself — extending the Cilium-first rule the static groups already
satisfy to every node Karpenter ever creates. Skip this and pods schedule onto a node with no CNI and
hang.

**The ≥ 8 GiB floor.** The NodePool sets `min_instance_memory_mib = 6144`, which excludes anything
smaller than 8 GiB (that live `r6g.medium` is exactly 8 GiB). The reason: the per-node DaemonSet slab —
Cilium, Beyla, Alloy, node-exporter, otel — eats a fixed ~3.2 GiB on every node regardless of workload.
On a 4 GiB `t4g.medium` that slab exhausts memory, the kubelet flaps `NotReady`, and the node churns. The
floor guarantees enough headroom that the slab is a tax, not a death sentence.

### The mandatory SCP exemption — the 403 that blocks every launch

This is the operational trap that will stump you on a rebuild if you don't know it. Karpenter tags the
instances it creates with governance tags — but it applies them via the launch template, not on the
`ec2:RunInstances` request. Two org SCPs sit above the account and reject that:

- `require-tagging` denies `ec2:RunInstances` when `Environment`/`ManagedBy`/`Owner` are absent from the
  request.
- `DenyTeamTagTampering` denies the `Team` tag on `ec2:CreateTags`.

So a non-exempt Karpenter controller gets a 403 on every single node launch. The fix lives in
[`mgmt/global/organizations`](https://github.com/asanexample/platform/blob/main/infra/live/aws/mgmt/global/organizations/terragrunt.hcl),
and note how it's written — anchored per cluster, not a leading wildcard:

```hcl
exempt_roles = [
  # ...
  "platform-use1-eks-karpenter-*", "preprod-use1-eks-karpenter-*",
]
```

That anchoring is a deliberate security choice from the audit: `platform-use1-eks-karpenter-*` matches the
module's `name_prefix`, so an unrelated role that merely contains `-karpenter-` can't inherit the
exemption via a sloppy `*-karpenter-*`. And this SCP change must be applied before Karpenter
first provisions, or the cluster can't build — a real rebuild-ordering dependency, not an afterthought.

---

## Part C — the descheduler: the maître d' who rebalances the room

Karpenter adds and removes nodes. It does not move a pod that's already placed — and neither does
the Kubernetes scheduler, which places a pod exactly once and never revisits the decision. That gap is a
real, bounded failure mode, and it has a name and a date.

A status note: [ADR-093](../../adrs/093-descheduler-node-rebalancing.md) is still marked
**Proposed**, but the descheduler is built and live on both clusters (shipped in #1106) — the ADR
header simply lags. Verify against the cluster, not the ADR status. Live proof:

```console
$ kubectl --context platform get cronjob -n kube-system descheduler
NAME          SCHEDULE       SUSPEND   ACTIVE   LAST SCHEDULE   AGE
descheduler   */15 * * * *   False     0        7m2s            4d21h

$ kubectl --context preprod get cronjob -n kube-system descheduler
NAME          SCHEDULE       SUSPEND   ACTIVE   LAST SCHEDULE   AGE
descheduler   */10 * * * *   False     0        2m3s            4d21h
```

### The incident that wrote the ADR

On **2026-07-02**, post-unpark, one preprod `t4g.large` absorbed **59 pods — ~99% of CPU requests, 189% of
memory limits** — while the other node sat at **14 pods (~40%)**. This wasn't a capacity problem: balanced
across the two nodes the same workload fits at ~69% each. It was a pure distribution problem, and the
consequences cascaded. The overloaded node's kubelet degraded to `NodeStatusUnknown`; every pod on it
crash-looped — including Karpenter's own controller. The one component that could have added relief
capacity was itself starved on the very node it would have relieved. Autoscaling deadlocked.

Why does everything pile onto one node? After a staggered unpark, the "emptiest node" — the one
the scheduler prefers — is the first node up, and a dozen independent single-replica controllers
(argo-rollouts, external-dns, kube-state-metrics, …) each independently pick it. `topologySpreadConstraints`
(ADR-085) don't help: they spread the replicas of one workload, not independent workloads. And manual
`kubectl delete` doesn't reliably fix it either — the scheduler frequently re-pins the pod to the same hot
node.

### The rebalancer, and its safety envelope

The fix is the [kubernetes-sigs descheduler](https://github.com/kubernetes-sigs/descheduler) running the
**`LowNodeUtilization`** strategy as a **CronJob** — a periodic sweep, the right shape for correcting
churn (unpark, consolidation, node replacement) rather than a hot loop. It evicts pods off nodes above the
overutilized thresholds so they reschedule onto nodes below the underutilized thresholds. This is the
maître d' — walking a lopsided dining room and moving parties to emptier tables.

The thresholds are per-cluster, and the reason is subtle:

| | underutilized (destination) | overutilized (source) | cadence |
|---|---|---|---|
| platform | 40% | 70% | every 15 min |
| preprod | 50% | 70% | every 10 min |

`LowNodeUtilization` only rebalances if some node qualifies as a destination — below all the
underutilized thresholds. In the 2026-07-02 incident the cool node sat at **39% CPU — one point under the
40% default**, which would have just barely qualified. Preprod raises the destination threshold to 50%
to give the emptier of two small nodes reliable headroom to be a valid target, and tightens cadence to 10
minutes because that's the cluster where a hot node actually melts down. Platform keeps the calm 40/70
defaults: bigger nodes, conservative `WhenEmpty` consolidation, and stateful services where fewer
evictions is better.

The maître d' analogy carries a critical caveat: only to a seat that fits, and never mid-meal. The
[descheduler
module](https://github.com/asanexample/platform/blob/main/infra/modules/descheduler/main.tf) enforces
exactly that through the `DefaultEvictor`:

- **`nodeFit: true`** — a pod is evicted only if it could actually be scheduled onto another node right
  now. This is the guard against the failure mode a naive `kubectl delete` hits: rebalancing never strands
  a pod `Pending`.
- **Respects [PodDisruptionBudgets](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)** —
  the ADR-085 workload PDBs and the CNPG database PDBs are never violated.
- **`evictSystemCriticalPods: false`** — pods at
  [`system-cluster-critical`](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/)
  and above (Karpenter, CoreDNS) are left in place. The descheduler doesn't move them — it protects them
  indirectly, by relieving the hot node around them.
- **Skips** DaemonSet, static/mirror, and controller-less pods, and never evicts pods with local storage
  (`evictLocalStoragePods: false`) — no data loss.

The elegant bit: the descheduler never touches Karpenter, yet it's what keeps Karpenter alive. By
rebalancing ordinary workloads off a hot node, it stops that node from degrading to the point where it
crash-loops the critical controllers sharing it. Three mechanisms, cleanly separated:
topology-spread spreads one workload's replicas, Karpenter adds and removes nodes, and the
descheduler moves existing pods between existing nodes — the gap neither of the others covers.

---

## Part D — the staff door: reaching a cluster with no public endpoint

The EKS API is **private-only** (ADR-010) — no public endpoint at all. So how do you run `kubectl`? Not
through a hole in the wall; through the campus's internal corridors. The primary path is
[Tailscale](https://tailscale.com/) (ADR-011), verified live as a `Connector`:

```console
$ kubectl --context platform get connector
NAME                              SUBNETROUTES    ISEXITNODE   ISAPPCONNECTOR   STATUS             AGE
platform-use1-eks-subnet-router   10.100.0.0/16   false        false            ConnectorCreated   23d
```

### How the subnet router works

A Tailscale subnet router runs as a pod inside the cluster and advertises the whole VPC CIDR
(`10.100.0.0/16` on platform, `10.101.0.0/16` on preprod) to your private **tailnet**. Join the tailnet
and every IP in that range becomes routable from your laptop — including the private EKS API endpoint and
any other in-VPC resource (Grafana, databases). The [Connector and
ProxyClass](https://github.com/asanexample/platform/blob/main/infra/modules/tailscale/main.tf) are CRDs, so
the config is in git; OAuth client credentials come from AWS Secrets Manager (`platform/tailscale/oauth`),
read via an OpenTofu Secrets Manager data source at apply time.

But an IP route isn't enough — you also need the API server's name to resolve. The API's DNS name only
answers with private IPs inside the VPC, via the VPC's own resolver. So the module publishes **split
DNS**: queries for `us-east-1.eks.amazonaws.com` and `aws.refplat.org` are routed to `10.100.0.2` — the
in-VPC Amazon-provided resolver, which always sits at VPC CIDR + 2. Now `aws eks update-kubeconfig`
followed by a plain `kubectl` just works, no tunnel, no public endpoint.

### The userspace-mode detail — two drivers, one steering wheel

The most consequential line in the Tailscale config is the two-drivers-grabbing-one-wheel problem. The
subnet router runs in **userspace mode** — `TS_USERSPACE=true`, set via the ProxyClass:

```yaml
spec:
  statefulSet:
    pod:
      tailscaleContainer:
        env:
          - name: TS_USERSPACE
            value: "true"
```

Default (kernel-mode) Tailscale creates its own `tun` interface and writes routes directly into the Linux
kernel routing table. But Cilium's eBPF dataplane owns that table. Two components both trying to
program kernel routing is the two-drivers problem: packet loss, routing loops. Userspace mode runs the
entire WireGuard tunnel inside the Tailscale process, off the kernel path — Tailscale gets its own wheel.
The cost is slightly higher CPU per byte, which is negligible for developer `kubectl` traffic. Where it
shares with the metaphor: both drivers are competent; the problem is purely that there's one wheel.
Where it breaks: unlike two literal drivers, kernel-mode Tailscale doesn't just fight for control — it
silently corrupts routing, so the symptom is dropped packets, not a visible struggle.

### The split-DNS bootstrap trap — locked in with the key inside

This trap has a name: **"`kubectl` times out even though I'm on Tailscale."** Split DNS points
the API hostname at `10.100.0.2` — a resolver only reachable through the subnet router. During a
bootstrap (or if the router pod is down), the name resolves before the route that makes the resolver
reachable exists. You've locked yourself in the room with the key on the inside: the thing that answers
"where is the API?" is itself only reachable once the API path is up. This is exactly why the module
creates the split-DNS records with a `depends_on` the Connector — DNS entries only appear after the subnet
router is online.

### The SSM fallback — a door independent of the cluster

Tailscale's weakness is circular: the operator pod runs on the cluster, so if the cluster is completely
down, so is Tailscale. The fallback is
[`scripts/eks-tunnel.sh`](https://github.com/asanexample/platform/blob/main/scripts/eks-tunnel.sh) — an
**SSM Session Manager** port-forward through an EC2 **bastion** that is entirely independent of EKS. It
discovers the bastion by `Name` tag, forwards `localhost:8443 → <eks-endpoint>:443`, and rewrites your
kubeconfig to point there. It even self-heals: SSM sessions die after ~20 min idle, so the script loops and
reconnects within ~2 seconds. It's the door that still opens when the building's own systems are dark.

### Operate, not author

One security note ties Parts A–C together. Whether you arrive via Tailscale or SSM, the role
`kubectl` assumes is **`PlatformAdmin`**, and ADR-040 rescoped it to operate, not author. Concretely:
the EKS access entry grants the AWS-managed `AmazonEKSViewPolicy` (broad read) plus a `platform-operator`
ClusterRole scoped to operate, not author. It grants `create` on the debug verbs — `pods/exec`,
`pods/portforward`, `pods/eviction` (drain), and throwaway debug pods (`pods` + `pods/ephemeralcontainers`,
for `kubectl run`/`debug`) — plus `delete`/`patch` on pods, `patch` on nodes (cordon) and on `apps`
workloads (`rollout restart`), `patch`/`update`/`delete` on a bounded named allow-list of operational
custom resources (Karpenter NodeClaims, Crossplane managed resources/XEnvironments, CNPG Clusters), and
cluster-wide `get`/`list`/`watch` on everything for debugging. The real boundary isn't "no `create`" — it's
no `create` on `apps`/Deployments and no arbitrary-CRD authoring. You can debug, drain, and restart to
your heart's content; you cannot hand-create a Deployment or edit a system namespace. Authoring goes through
GitOps — even the humans who run the platform hold no standing power to rewrite it by hand. (The one real residual: `pods/exec` lets a
shell read that pod's mounted secrets and reach its Pod-Identity credentials — a deliberate trade for
debuggability, noted in the ADR.)

---

## Gotchas that teach

- **The floor can't be Karpenter, ever.** Karpenter can't provision its own node — so a fixed system group
  must always exist, and it must be big enough to hold the DaemonSet slab plus the standing stack plus
  any node-pinned DaemonSet pod. That's why platform's floor is `t4g.xlarge`, not `large`.
- **`instance_types` is ForceNew — and it evicts the subnet router.** A one-line node-type resize destroys
  and recreates the managed group (~3-min blip) and takes the in-cluster Tailscale router with it, briefly
  cutting private API access. Plan it as maintenance.
- **Encryption isn't optional — the SCP refuses the launch.** An unencrypted root volume doesn't get a
  warning; `DenyUnencryptedEbsOnLaunch` blocks the instance from starting at all.
- **Karpenter's 403 is above the account.** No node launches + `UnauthorizedOperation` on `RunInstances`
  means the SCP exemption is missing or misspelled — it lives in `mgmt/global/organizations`, anchored per
  cluster, and must be applied before first provision.
- **The 8 GiB floor is a kubelet-stability floor, not a preference.** The ~3.2 GiB DaemonSet slab exhausts
  a 4 GiB node and flaps it `NotReady`; `min_instance_memory_mib = 6144` keeps it stable.
- **The descheduler's ADR says Proposed; the cluster says live.** Trust the CronJob (`AGE 4d21h`), not the
  header. Verify status against primary sources.
- **`nodeFit: true` is the difference between rebalancing and an outage.** Without it, eviction can strand a
  pod `Pending` — which is exactly why naive `kubectl delete` isn't a fix.
- **Userspace Tailscale isn't a preference — it's coexistence with Cilium.** Kernel mode silently corrupts
  routing by fighting eBPF for the kernel table.
- **Split DNS is a bootstrap chicken-and-egg.** The resolver that answers "where is the API?" is only
  reachable through the API path — so a `kubectl` timeout on a fresh cluster is usually the router being
  down, not your auth.

## Go deeper — source of truth

- [ADR-078 — Cluster elasticity (Karpenter + workload autoscaling)](../../adrs/078-cluster-elasticity-karpenter.md)
  — the two-layer model, Cluster-Autoscaler rejection, the startup-taint and SCP as-built notes.
- [ADR-093 — Descheduler for node rebalancing](../../adrs/093-descheduler-node-rebalancing.md) — the
  2026-07-02 incident and the LowNodeUtilization thresholds (status lags reality — it's live).
- [ADR-011 — Tailscale for private cluster access](../../adrs/011-tailscale-for-private-cluster-access.md)
  and [ADR-010 — Private EKS API endpoint](../../adrs/010-private-eks-api-endpoint.md).
- [ADR-040 — Platform engineer access model](../../adrs/040-platform-engineer-access-model.md) — the
  operate-not-author rescoping of `PlatformAdmin`.
- Modules: [`aws/eks-node-group`](https://github.com/asanexample/platform/blob/main/infra/modules/aws/eks-node-group/main.tf),
  [`aws/karpenter`](https://github.com/asanexample/platform/blob/main/infra/modules/aws/karpenter/main.tf)
  (+ the [NodePool chart](https://github.com/asanexample/platform/blob/main/infra/modules/aws/karpenter/charts/nodepool/templates/nodepool.yaml)),
  [`descheduler`](https://github.com/asanexample/platform/blob/main/infra/modules/descheduler/main.tf),
  [`tailscale`](https://github.com/asanexample/platform/blob/main/infra/modules/tailscale/main.tf).
- The **cluster-parking** and **cluster-access** house skills for the operational procedures.
- Back to the [Foundations orientation](orientation.md).
