# Learn: Foundations — the cluster & Cilium (deep dive)

Two facts about the cluster are worth earning in full: the EKS control plane has no public door, and
the network fabric inside is [Cilium](https://cilium.io/) on [eBPF](https://ebpf.io/what-is-ebpf/),
not the default. This dive covers why private-only is a genuinely different security posture, and why a
cluster that ships with no networking has to be built in four ordered pieces. The terse facts live in the
[Foundations reference](reference.md).

The single idea everything else hangs off:

> **An EKS cluster in this platform is born with no nervous system.** AWS is told to install *no* CNI and
> *no* kube-proxy. Until Cilium lands, the cluster can authenticate you, schedule nothing useful, and hand
> out no pod IPs. That one choice — "bring your own CNI" — is what forces the four-layer build, forbids a
> monolithic module, hands packet routing to eBPF, and creates a fistful of chicken-and-egg traps the
> platform has to defuse one at a time.

## The frame: a control plane with no door to the street

Start with the door — it's the cheapest thing to verify and the easiest to get wrong. The EKS API
endpoint is private-only ([ADR-010](../../adrs/010-private-eks-api-endpoint.md)). Ask the live platform
cluster what its endpoint posture is — and note the `--output json`, because `--output text` prints these
booleans in *alphabetical column order* with no headers and will happily convince you public access is on
when it isn't:

```console
$ AWS_PROFILE=platform aws eks describe-cluster --name platform-use1-eks \
    --query 'cluster.resourcesVpcConfig.{public:endpointPublicAccess,private:endpointPrivateAccess}' \
    --output json
{
    "public": false,
    "private": true
}
```

The preprod cluster answers identically (`public: false, private: true`). The API server's DNS name
resolves only to private IPs inside the VPC; from the public internet it resolves to nothing you can route
to.

This is a real security property, not a checkbox. A public endpoint with an IP allowlist is **one gate**:
your AWS credentials. The network is open to the world — the allowlist just narrows *which* world.
Private-only is a **double gate**: you need valid IAM credentials (SigV4) *and* a network path that lands
inside the VPC. A stolen `kubectl` token is useless from a coffee shop, because there is no route from the
coffee shop to the API server at all. That's the difference between "we trust the lock" and "there is no
door on the street to pick" — the building-with-no-street-entrance idea. It's also the concrete thing that
lets the platform claim HIPAA/PCI-tier network isolation: "the control plane is not reachable from the
internet" stops being a policy you enforce and becomes a fact of the topology.

And the default is *closed*. The module's `endpoint_public_access` variable defaults to `false`:

```hcl
variable "endpoint_public_access" {
  description = "Enable the public API server endpoint. Defaults to false — private-only is the house
                 policy (ADR-010); reach the API over Tailscale/SSM. Set true only deliberately..."
  type        = bool
  default     = false
}
```

That's fail-safe design: a *dropped* config line can't silently expose the API, because the absent value
falls back to closed, not open. (How you actually reach a private API — Tailscale — is the
[Nodes, scaling & access deep dive](deep-dive-nodes-scaling-access.md); it's that module's topic, not this
one's.)

## The core: a cluster born with no nervous system

One line in the EKS module shapes everything downstream (`infra/modules/aws/eks/main.tf`):

```hcl
resource "aws_eks_cluster" "this" {
  # ...
  # BYOCNI mode: disables default VPC CNI and kube-proxy. Cilium provides both.
  bootstrap_self_managed_addons = false
  # ...
}
```

Normally EKS pre-installs three DaemonSets for you: the AWS VPC CNI, kube-proxy, and CoreDNS. Setting
`bootstrap_self_managed_addons = false` tells AWS to install none of the networking — no CNI, no
kube-proxy ([ADR-008](../../adrs/008-cilium-as-cross-cloud-cni.md)). This is deliberate: if the AWS VPC CNI
were installed, it would fight Cilium for control of pod networking. So the cluster comes up able to
*authenticate* API calls but unable to give a single pod an IP address.

That has a sharp consequence. **A pod can't get an IP until a CNI is running — and CoreDNS is a pod.** So
is every add-on, and every workload. You cannot build this cluster in one `apply`, because there's a
mandatory human-invisible step in the middle: "wait for a Helm chart to install the CNI, then continue."
Terraform has no way to express "create the cluster, pause for an out-of-band Helm release against that
cluster, *then* create the node groups" inside a single module — the Helm provider needs the cluster's
endpoint to even configure itself, which is a circular dependency if it lives in the same module that
*creates* the cluster.

The answer ([ADR-009](../../adrs/009-eks-component-separation.md)) is to split the build into four ordered
Terragrunt units, each its own module and its own state file:

```text
eks  →  cilium  →  node-groups  →  eks-addons
```

The order isn't arbitrary — each layer physically needs the one before it:

| Unit | Creates | Why it must wait |
| --- | --- | --- |
| `eks` | The cluster, OIDC provider, KMS key, access entries | Nothing to wait for — but it ships **no** CNI |
| `cilium` | The Cilium Helm release + Gateway API CRDs | Needs the API server to exist to install into |
| `node-groups` | Managed node groups, node IAM role | Nodes with no CNI can't configure pod networking |
| `eks-addons` | CoreDNS, EBS CSI driver, the gp3 StorageClass | These are **pods** — they need a CNI *and* a node to land on |

The CoreDNS chicken-and-egg is the cleanest illustration of the whole rule. CoreDNS is the cluster's DNS
server — but it's a Deployment, so it needs a pod IP, so it needs Cilium, so it *cannot* be a
cluster-creation add-on. It has to come dead last, in `eks-addons`, after both a CNI and nodes exist. Try
to install it earlier and its pods sit `Pending` forever with no IP to schedule onto.

One live detail makes the ordering vivid. The Cilium unit sets `helm_wait = false`:

```hcl
# Must not wait — Cilium deploys before node groups exist (BYOCNI ordering)
helm_wait = false
```

Helm's default is to block until the release's pods are `Ready`. But Cilium's agent runs as a DaemonSet —
one pod per node — and at the moment Cilium installs, **there are no nodes yet** (they're the *next* unit).
If Helm waited for Ready pods it would hang until timeout on a cluster that structurally can't satisfy it.
So the apply installs the chart and moves on; the agents materialize a layer later when node-groups bring
nodes up. The dependency graph, not a Helm health check, is what guarantees correctness.

### The danger this buys

State isolation is a feature — a failed `node-groups` apply can't corrupt the `eks` state. But the same
separation hands you a loaded gun. The units apply in the order above and **destroy in reverse**
(`eks-addons` → `node-groups` → `cilium` → `eks`). Destroying the `cilium` unit *by itself*, out of order,
rips the CNI out from under every running node — pods keep existing but lose all networking, cluster-wide,
instantly. ADR-009 flags this explicitly as the one risk the separation introduces. The four units make it
*impossible to build the cluster in the wrong order*, but they do nothing to stop you *destroying* one in
the wrong order. `terragrunt destroy` in the `cilium` directory is a cluster outage with a friendly-looking
plan.

## The datapath: what eBPF actually does once Cilium is up

Cilium **replaces kube-proxy entirely**. That's not a tuning knob here — it's mandatory, and the module
makes it non-negotiable for AWS. In `infra/modules/cilium/main.tf`, the per-cloud "plumbing" block for AWS
hardcodes:

```hcl
cloud_plumbing = {
  aws = merge(
    {
      kubeProxyReplacement = true                                     # Required: EKS BYOCNI deploys no kube-proxy DaemonSet
      hubble               = { tls = { auto = { method = "helm" } } } # Avoids BYOCNI post-install hook chicken-and-egg
    },
    # ...
  )
}
```

These values are merged *after* the generic and datapath defaults in the Helm value stack (only the
k8s-API host/port document follows, and it shares no keys), so they win over any generic default — on AWS,
`kubeProxyReplacement` is `true`, full stop. Why mandatory? Because there is no kube-proxy to fall back to.
`bootstrap_self_managed_addons = false` meant AWS never installed the kube-proxy DaemonSet. If Cilium
didn't take over the job, Kubernetes Services simply *would not work* — a connection to a Service's
`ClusterIP` or a `NodePort` would have nothing implementing it and would be refused. Cilium isn't optimizing
kube-proxy away; it's the only thing doing the job at all.

You can watch this be true. Ask the live cluster what DaemonSets exist in `kube-system`:

```console
$ kubectl --context platform -n kube-system get ds
NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR              AGE
cilium                   3         3         3       3            3           kubernetes.io/os=linux     23d
cilium-envoy             3         3         3       3            3           kubernetes.io/os=linux     23d
ebs-csi-node             3         3         3       3            3           kubernetes.io/os=linux     23d
ebs-csi-node-windows     0         0         0       0            0           kubernetes.io/os=windows   23d
eks-pod-identity-agent   3         3         3       3            3           <none>                     23d

$ kubectl --context platform -n kube-system get ds kube-proxy
Error from server (NotFound): daemonsets.apps "kube-proxy" not found
```

There's `cilium` (the agent) and `cilium-envoy` (the Gateway API proxy, we'll get there), and there is
*literally no* `kube-proxy`. The image confirms the pinned version from `infra/live/aws/_versions.hcl`
(`cilium = "1.19.4"`):

```console
$ kubectl --context platform -n kube-system get ds cilium \
    -o jsonpath='{.spec.template.spec.containers[*].image}'
quay.io/cilium/cilium:v1.19.4@sha256:2eb67991…
```

### Why eBPF beats the iptables it replaced

This is the substrate, and it's why the platform bothers. The old kube-proxy implements every Service as a
chain of **iptables** rules in the kernel's netfilter tables. To route a packet to one of a Service's
backends, the kernel walks that chain **top to bottom, linearly**, rule by rule, for *every* packet — and
every time a pod is added or removed, the ruleset is rewritten. On a small cluster you never notice. On a
cluster with thousands of Services and endpoints, the chains grow into the tens of thousands of rules,
per-packet latency climbs, and a single endpoint change can stall the datapath while iptables reprograms.

Cilium does the identical job with **eBPF programs** — small, verified programs the kernel runs at the
network hooks — backed by eBPF hash maps. A Service lookup becomes a hash-map read: effectively **O(1)**,
constant-time regardless of how many Services exist, and updated *in place* (change one map entry) rather
than by rewriting a linear ruleset.

> **iptables is a paper phone directory you read cover to cover to find one number; eBPF is the
> hash-indexed contacts app on your phone.** Both map a name to a number. The directory's lookup time grows
> with the book and it has to be reprinted whenever a number changes; the app is one tap no matter how many
> contacts you have. **Where the metaphor breaks:** a contacts app is a userspace convenience — eBPF runs
> *in the kernel*, at the packet hook, with no context switch to userspace at all, which is a second, orthogonal
> reason it's fast that the analogy doesn't carry.

That's the whole "eBPF beats iptables" claim, grounded: constant-time hash lookups plus in-place updates
plus in-kernel execution, versus linear chain-walks plus full reprograms.

## The chicken-and-eggs Cilium has to defuse

BYOCNI's "no pods until the CNI is up" rule keeps generating variants of the same trap: something Cilium
needs, needs a pod, needs Cilium. Two are worth seeing because the fix is a real design decision, not an
accident.

**Hubble TLS via the `helm` method.** [Hubble](https://docs.cilium.io/en/stable/gettingstarted/hubble/) is
Cilium's flow-observability layer, and its components talk to each other over mutual TLS — so somebody has
to mint certificates. The obvious tool is [cert-manager](https://cert-manager.io/). But cert-manager runs
as *pods*, and pods need a CNI, and the CNI is the very thing being installed. Reaching for cert-manager to
bootstrap Cilium's own certs is a perfect circular dependency. So the AWS plumbing pins
`hubble.tls.auto.method = "helm"` — the Helm chart generates the certs itself, in-process, needing nothing
already running in the cluster. It's a deliberate trade (ADR-008 lists it as a negative: Hubble's certs
aren't integrated with the platform's cert-manager) accepted to break the cycle.

**The Gateway API ingress identity — the one that bites people writing policy.** Cilium's Gateway API runs
an external [Envoy](https://gateway-api.sigs.k8s.io/) proxy — the `cilium-envoy` DaemonSet you saw above —
with `hostNetwork`. When Envoy forwards a request to your backend pod, the packet's source is **not** the
node's IP and **not** the `host` identity you'd guess. Cilium stamps it with a *reserved* identity —
**`ingress`, identity number 8** ([ADR-008](../../adrs/008-cilium-as-cross-cloud-cni.md)).

Why this matters: Cilium enforces network policy by **identity**, not by IP. If you write a
CiliumNetworkPolicy to protect an environment namespace and you allow traffic by CIDR (`ipBlock`), it
*silently does nothing* for gateway traffic — because the source IP already has a known identity (8) in
Cilium's ipcache, and identity-based matching takes precedence over the CIDR rule. The connection is
dropped, DNS and TLS look perfectly healthy, and you get an `upstream connect error` with no obvious cause.
The fix is to allow the identity, not the address:

```yaml
# CiliumNetworkPolicy ingress rule — allow gateway traffic by IDENTITY, not CIDR
ingress:
  - fromEntities:
      - ingress          # reserved identity 8 — Cilium's Gateway API Envoy
```

Think of identity 8 as a badge the reception desk clips onto every visitor before sending them into the
building. Your floor's door reader is programmed to check *badges*, not to recognize faces or street
addresses. Writing an `ipBlock` rule is like posting a guard who only checks home addresses — he'll turn
away every badged visitor because that's not what he was told to look for. (In this platform you rarely write
this rule by hand: the Crossplane Environment Composition adds `fromEntities: ["ingress"]` to every
environment namespace automatically. The trap is a *hand-rolled* namespace that silently blackholes its own
ingress.)

One last detail rides along with the gateway: the listener's TLS secret is copied into a dedicated
namespace. A Gateway listener that references a TLS secret needs that secret to exist in the
`cilium-secrets` namespace, renamed `<source-namespace>-<secret-name>` — e.g. a Gateway in `default` using
`platform-gateway-tls` gets a copy at `cilium-secrets/default-platform-gateway-tls`. Cilium's operator syncs
this for you (`enable-gateway-api-secrets-sync=true`, `gateway-api-secrets-namespace=cilium-secrets` in
`cilium-config`); the platform's gateway-config only creates the HTTPRoutes — it does not copy the secret.

## Gotchas

- **`--output text` on `describe-cluster` will lie to you.** It prints the VPC-config booleans in
  alphabetical column order with no headers, so `endpointPublicAccess` and `endpointPrivateAccess` are
  trivially transposable by eye. Always use `--output json` (or a scoped `--query`) when you're checking
  whether the API is exposed. A security check you can misread is worse than none.
- **Destroying the `cilium` unit alone is a cluster-wide outage, not a config change.** The four-unit
  separation makes the *build* order un-violable but does nothing for *destroy* order. Pulling the CNI out
  from under running nodes drops all pod networking instantly. Destroy in reverse (`eks-addons` →
  `node-groups` → `cilium` → `eks`) or not at all.
- **CoreDNS can never be a cluster-creation add-on here.** It's a pod; pods need a CNI; the CNI is BYO. If
  you find CoreDNS pods stuck `Pending` with no IP, the question is never "what's wrong with CoreDNS" — it's
  "is Cilium up and are there nodes for it to land on."
- **`kubeProxyReplacement` isn't tunable on AWS.** There is no kube-proxy DaemonSet to fall back to. If
  Services stop resolving to backends, don't look for a broken kube-proxy; look at whether Cilium's agent is
  healthy, because it's the *only* Service implementation.
- **Write CiliumNetworkPolicy by identity, not by CIDR, for anything behind the Gateway.** Gateway→pod
  traffic wears reserved identity `ingress` (8); an `ipBlock` CIDR rule silently won't match it. Symptom:
  `upstream connect error` with healthy DNS and TLS. Fix: `fromEntities: ["ingress"]`.
- **New Karpenter nodes come up tainted `node.cilium.io/agent-not-ready`** — the "wet paint, do not sit"
  sign that repels pods until Cilium's agent lands on the node and removes it, extending the Cilium-first
  rule to nodes that appear at 3 a.m. It's detailed in the
  [Nodes, scaling & access deep dive](deep-dive-nodes-scaling-access.md); flagged here so you know why a
  brand-new node briefly refuses pods.

## Source of truth

- **[ADR-010 — Private-Only EKS API Endpoint](../../adrs/010-private-eks-api-endpoint.md)** — the double
  gate, the per-cluster status, and the one bootstrap exception where the public endpoint is toggled.
- **[ADR-009 — EKS Component Separation](../../adrs/009-eks-component-separation.md)** — the four units, the
  alternatives rejected (monolith + provisioners, monolith + `depends_on`), and the destroy-order risk.
- **[ADR-008 — Cilium as Cross-Cloud CNI](../../adrs/008-cilium-as-cross-cloud-cni.md)** — BYOCNI, the
  overlay datapath, `kubeProxyReplacement`, the ingress identity, Hubble TLS, and the `cloud_provider` model.
- **Code:** `infra/modules/aws/eks/main.tf` (`bootstrap_self_managed_addons`, endpoint config) and
  `infra/modules/aws/eks/variables.tf` (the fail-safe `endpoint_public_access = false` default);
  `infra/modules/cilium/main.tf` (the `cloud_plumbing.aws` block — `kubeProxyReplacement`, Hubble method,
  the Helm value merge order); `infra/live/aws/_versions.hcl` (the Cilium `1.19.4` pin); and the live unit
  `infra/live/aws/platform/us-east-1/platform/cilium/terragrunt.hcl` (`cloud_provider = "aws"`,
  `helm_wait = false`).
- **Substrate:** [Cilium](https://cilium.io/) · [what eBPF is](https://ebpf.io/what-is-ebpf/) ·
  [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/) ·
  [Kubernetes virtual IPs / kube-proxy](https://kubernetes.io/docs/reference/networking/virtual-ips/) ·
  [EKS cluster endpoint access](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html) ·
  [Gateway API](https://gateway-api.sigs.k8s.io/). All current as of Cilium 1.19 / Kubernetes 1.35.
- **Related:** [Foundations orientation](orientation.md) · the terse lookup in
  [Foundations reference](reference.md).
