# Learn: The Agentic Platform — the XAgent runtime (deep dive)

This platform runs an agent the way you'd run a contractor you don't trust: through the same governed
front door as any workload. This deep dive takes one stop apart — how a single git-committed `XAgent`
claim becomes a locked-down runtime *slot* on the hub, and the GitOps control plane that keeps it
reconciled. For the wider picture, see the [agentic orientation](orientation.md); for a terse lookup,
the [Reference](reference.md).

**Status, up front and honest.** Everything here is checked against the repo code — the `agent-api`
chart, the Composition, the XRD, `gitops/agents/`, `argocd-apps/agents.tf` — and the ADR-082 status
header (Accepted 2026-06-25, built and live 2026-06-26, epic #718). The hub cluster is parked this
session, so I couldn't `kubectl` the running objects; where a live-behavior claim matters, I lean on
the code path that produces it. There is exactly one `XAgent` today, the triage copilot. This is not a
fleet.

---

## One parallel: `XAgent` : agent :: `XEnvironment` : tenant

An `XAgent` is to a platform agent what an `XEnvironment` is to a tenant — not a loose analogy, the
same machine pointed at a different shape. Both are [Crossplane](https://docs.crossplane.io/latest/)
**composite resources**: a single declarative object that a **Composition** (a pipeline of functions)
reconciles into a bundle of real resources. Both split *provisioning* (Crossplane makes the slot) from
*delivery* (ArgoCD ships the workload into it). The only difference is what each is shaped for.

> *If an `XEnvironment` provisions an **apartment** for a tenant to move into — quotas, stages, domains, a
> lease — an `XAgent` provisions a **guard booth** on the hub: a tiny, locked-down slot with read-only
> windows into the building and exactly one phone line out, to the model. Same construction crew, same
> permits office; radically smaller, more locked-down structure.*
> **Where the metaphor breaks:** a guard booth is *staffed* by whoever you post there — the booth (the slot)
> is inert until ArgoCD delivers the agent's actual workload into it. The Composition builds the booth and
> its phone line; it never hires the guard.

One structural fact drives the whole security story. Look at the XRD:

```yaml
# infra/modules/crossplane/charts/agent-api/templates/xagent-xrd.yaml
apiVersion: apiextensions.crossplane.io/v2
kind: CompositeResourceDefinition
metadata:
  name: xagents.platform.refplat.org
spec:
  scope: Cluster
  group: platform.refplat.org
  names: { kind: XAgent, plural: xagents }
```

Two things there matter. First, `apiextensions.crossplane.io/v2` with `scope: Cluster` — Crossplane v2's
cluster-scoped composite, where the `XAgent` *is* the claim. There is no separate namespaced claim kind
proxying to a cluster XR, the way v1 worked; you write the composite directly. If you learned Crossplane
on v1 tutorials, unlearn the claim-vs-XR split here — it teaches a wrong model. Second, and because of
that: creating an `XAgent` at all requires cluster-level RBAC. A cluster-scoped resource isn't in anyone's
namespace, so no tenant can self-provision one — the first gate is Kubernetes' own authorization. That's
why the claim lives in `gitops/agents/`, is admin-gated (a CODEOWNERS rule routes it to a platform admin),
and is validated twice before it reaches the cluster. The scope choice is itself a security control.

---

## The claim: what you actually write

Here is the one real claim, verbatim (`gitops/agents/triage-copilot.yaml`), trimmed of its comments:

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata:
  name: triage-copilot          # → ns platform-agent-triage-copilot; SA + IAM role named from it
spec:
  team: platform                # required — join key to gitops/products/<team>/<product>.yaml
  product: triage-copilot       # required — image/ECR scope + signing identity (supply chain, ADR-081)
  placement: { cluster: platform }              # enum ["platform"] — hub-only (ADR-082 D2)
  model: { provider: bedrock, id: us.anthropic.claude-sonnet-4-6 }   # id PINNED (ADR-074)
  obsRead: true                 # bind the read-only obs ClusterRole to the agent's SA — NO Secrets
  awsPermissions:
    policyStatements:           # extra IAM, deny-set validated + boundary-capped
      - { sid: WriteEvalCorpus, actions: [s3:PutObject, s3:GetObject], resources: ["arn:aws:s3:::platform-agent-eval-corpus/*"] }
      # …plus a KMS statement for the corpus CMK
  autonomy: { mode: propose-only }              # enum is propose-only ONLY — the safety invariant
  trigger:   { kind: alertmanager-webhook }     # informational — the route is wired separately
  lifecycle: { phase: active }                  # active | suspended (the kill-switch)
```

Every field earns its place, and the absences teach as much as the presences. `team` and `product` are
the only required fields; they join to the `Product` registry so the agent's image, ECR scope, and
signing identity come from the same supply chain as any tenant workload (ADR-081, unchanged — more below).
`placement.cluster` is an `enum: ["platform"]`, so the schema cannot express running an agent anywhere but
the hub. `model.id` is a pinned string — no floating "latest"; a model change is a new release.
`autonomy.mode` is an `enum: ["propose-only"]` with exactly one member: the API can't even represent an
autonomous agent today. That's the safety floor, enforced in the schema. `maxConcurrent` (default `4`) and
`tokenBudget` are informational to the Composition — the runner enforces them, not Crossplane.
`trigger.kind` is informational too; the real Alertmanager route is wired elsewhere. And `access.clusters`
(cross-cluster read) is schema-only, Phase 2, deferred — the field lands now so claims stay
forward-compatible, the roles come later.

---

## The Composition: one go-template, rendered into a slot

The Composition (`files/composition.yaml`) is a Pipeline of three functions — the same three as the tenant
`XEnvironment` Composition, which is the point:

```yaml
mode: Pipeline
pipeline:
  - step: load-config      # function-environment-configs — pulls the hub's cluster constants into context
  - step: render-resources # function-go-templating — the inline template that renders every resource
  - step: ready            # function-auto-ready — marks the XAgent Ready when its composed resources are
```

`function-environment-configs` loads an `EnvironmentConfig` named `platform-agent-config` — the per-cluster
constants that don't belong in a claim (`clusterName`, `region`, `workloadAccountId`, the
permissions-boundary ARN). It's Helm-templated from the module's inputs (`agentconfig.yaml`), so the
Composition itself stays cluster-agnostic and the go-template reads `.context`.

**The two-file trick.** The template is full of Crossplane's own `{{ }}` delimiters, which Helm — packaging
this chart — would try to evaluate and mangle. The fix: the template ships as a raw file in `files/`, and a
one-line `templates/composition.yaml` emits it verbatim:

```gotemplate
{{ .Files.Get "files/composition.yaml" }}
```

`.Files.Get` copies the bytes through untouched, so the go-template delimiters reach Crossplane intact.
It's the identical pattern the `environment-api` chart uses; if you ever see a Composition's `{{ }}` come
out half-evaluated, this is the trap. The whole thing is render-tested offline with `crossplane render` —
no cluster needed, which is also how you can safely poke at it (see "Make it break" below).

### What the template renders — the slot

Walking the template top to bottom, an active `XAgent` composes:

1. **Namespace `platform-agent-<name>`** — labelled with the team/product and, crucially,
   [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/) at
   `enforce: baseline`, `warn`/`audit: restricted`. Past the 63-char DNS limit the name is
   truncated-and-hashed (`substr 0 56` + a 6-hex `sha256sum` suffix) — a detail the ArgoCD side has to
   replicate exactly (it does; see below).
2. **A named ServiceAccount** (= the `XAgent` name, same truncate-and-hash) — the identity the agent's pod
   will run as. The workload references it; the Composition just creates it.
3. **An IAM `Role` `Pod-platform-agent-<name>`** — trust policy is
   [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html): principal
   `pods.eks.amazonaws.com`, actions `sts:AssumeRole` + `sts:TagSession`, `Condition` pinning
   `aws:SourceAccount` to the workload account, and — if configured — a `permissionsBoundary` that caps
   whatever the role can ever hold.
4. **A `RolePolicy`** — the model's Bedrock data-plane grant (`bedrock:InvokeModel`,
   `InvokeModelWithResponseStream`, `Converse`, `ConverseStream`) on `foundation-model/*` +
   `inference-profile/*` only — *invoke, never manage* — plus the claim's `awsPermissions` statements
   appended. No `bedrock:*`, no management actions, anywhere.
5. **The `PodIdentityAssociation`** — binds the SA to the role, rendered only when `active`. This one
   conditional is the kill-switch: flip `lifecycle.phase` to `suspended` and this resource vanishes. The
   pod keeps running but loses its AWS credentials, so it can't invoke Bedrock — it can't reason. A
   dead-man's switch that removes the fuel, not one that asks the engine to stop.
6. **The obs-read `ClusterRoleBinding`** — only if `obsRead: true`. It binds the fixed, platform-owned
   `platform-trust-observability-reader` ClusterRole (read of pods/events/services/deployments + ArgoCD
   `Applications` + the `Product` registry — and pointedly no Secrets) to the named SA, not the whole
   namespace. The agent can be bound to that role but can never redefine what it grants.
7. **NetworkPolicies** — a default-deny ingress, an allow-trigger ingress from `observability` + `kube-system`
   on `:8080`, and a `CiliumNetworkPolicy` for egress (default-deny, opening only DNS, kube-apiserver, the
   host-local Pod-Identity agent, the in-cluster obs/directory/keycloak namespaces, and
   `toFQDNs` for Bedrock + Slack + `api.github.com`).

What it does *not* render: the agent's Deployment, Service, and `/metrics` ServiceMonitor. That's ArgoCD's
job. Provisioning is separate from delivery — the Composition (gated IaC) owns the namespace, identity,
RBAC, and network; the signed workload arrives separately. Hold that line; the whole control plane depends
on it.

---

## The GitOps control plane: a commit is the only verb

Provisioning is IaC, so you might expect adding an agent to be a `terragrunt apply`. It isn't — and that's
the GitOps-native promise of ADR-082 D4. The chart is installed once on the hub by the `crossplane` module
(`enable_agent_api = true` on the hub unit; note `enable_environment_api` stays off there — the hub
provisions agents, not tenants, so ADR-048 holds). After that one apply, adding an agent is a git commit.
Two ArgoCD pieces, both in `argocd-apps/agents.tf`, make that true, and both target the hub, unlike tenant
delivery which targets a workload cluster:

- **The `agents` registry-sync.** An `Application` syncs `gitops/agents/*.yaml` onto the hub's
  `crossplane-system`, so Crossplane sees each `XAgent` and reconciles it. Its `AppProject` is deliberately
  the tightest possible: `clusterResourceWhitelist` is only `{ group: platform.refplat.org, kind: XAgent }`,
  and `namespaceResourceWhitelist` is `[]`. That sync road can create `XAgent`s and nothing else — a
  compromised registry commit can't project some rogue ClusterRole onto the hub.
- **A per-agent workload ApplicationSet** (`agent-<name>`) fans over `gitops/releases/<team>/<product>/*.yaml`
  — the promoted, signed image digest (ADR-071) — and delivers the Deployment/Service into the
  Composition-made namespace. Its `AppProject` has `clusterResourceWhitelist: []` — no cluster-scoped writes
  at all — and its namespaced whitelist notably excludes ServiceAccount: the Composition owns the SA, so the
  app must drop its own SA manifest. Delivery physically cannot forge identity.

So the two roads are separated by AppProject blast radius: the registry road may write exactly one
cluster-scoped kind (`XAgent`); the delivery road may write zero. Neither can do the other's job. Adding a
second agent is: write `gitops/agents/<name>.yaml`, add the `agent-<name>` project + appset (the
`for_each = local.agents` handles the fan-out), open the admin-gated PR. No per-agent infra apply.

> One correctness detail worth naming: the namespace truncate-and-hash logic is duplicated in two languages
> — the go-template (`sha256sum`, `substr`) and the Terraform that computes `agent_ns` for the
> ApplicationSet (`sha256(...)`, `substr(...)`). They must agree, or ArgoCD would target a namespace the
> Composition never made. They do — both take 56 chars plus 6 hex — but it's the kind of drift a future edit
> could introduce on one side only.

---

## Why the hub, and why Bedrock needed an SCP change

Two decisions here are scar tissue from a real mistake, and they teach better than the happy path.

**Why the hub, not preprod.** ADR-081 reached for one delivery road — correct for the supply chain — but
over-corrected and unified runtime placement too, routing the agent through the tenant `XEnvironment` model
as a `platform`-team product. With per-environment placement deferred, the agent landed on preprod, a
workload cluster, where its observability (Loki/Mimir/Tempo) and its trigger (Alertmanager) are all
hub-resident and unreachable. The agent ran but was blind, correctly abstaining on every alert. ADR-082
fixes exactly that: runtime forks by workload type. A tenant gets an `XEnvironment` on a workload cluster; a
platform agent gets an `XAgent` on the hub, where the signals already live. The `platformTrust` envelope
ADR-081 invented to force a platform-infra tool into a tenant shape became vestigial — the tell that the
shoe never fit.

**Why Bedrock touched an org SCP (D8).** The pinned model `us.anthropic.claude-sonnet-4-6` is a
cross-region inference profile — it routes invocations across `us-east-1`, `us-east-2`, and `us-west-2`.
The org `deny-regions` SCP would block the out-of-primary-region calls, so its `NotAction` was broadened for
the Bedrock data-plane actions only; management actions stay region-pinned. It's recorded in the ADR
precisely so it reads as a deliberate, scoped decision and not a silent SCP edit. (Bedrock access is
per-account too: the model grant is minted in the agent's own account, and requires a model-access agreement
there.)

---

## Gotchas

- **RBAC ≠ reachability.** `obsRead: true` grants the authorization to read obs — it does not open the
  network path. A hub agent still needs the egress CiliumNetworkPolicy (to reach the obs namespaces and
  Bedrock) and the ingress allow (for the Alertmanager webhook). Two independent planes; a green RBAC check
  with a red network policy still fails, silently.
- **A k8s `ipBlock` egress rule doesn't work here.** The agent's real destinations can't be expressed as
  CIDRs on Cilium: in-cluster obs is identity-matched (Cilium endpoints, not IPs), the Pod-Identity
  credential agent (`169.254.170.23`) is host-local traffic, and Bedrock/Slack are dynamic IPs behind FQDNs.
  That's why egress is a `CiliumNetworkPolicy` with `toEndpoints` + `toEntities: [host]` +
  [`toFQDNs`](https://docs.cilium.io/en/stable/security/policy/language/#dns-based), not a stock
  `NetworkPolicy` `ipBlock`. Reach for an ipBlock and it will quietly deny everything the agent needs.
- **`obsRead` binds a fixed role — you can't widen it from the claim.** The bound
  `platform-trust-observability-reader` is platform-owned and has no Secrets verb. An agent that "needs more
  read" doesn't get a bigger claim field; a platform admin changes the role (a platform decision), or the
  agent goes without.
- **The SA is not yours to deliver.** The per-agent AppProject omits ServiceAccount from its whitelist on
  purpose. If an agent's `k8s/` overlay ships its own SA manifest, ArgoCD refuses it — the Composition
  already made it.
- **Don't `kubectl scale` the agent to stop it.** GitOps self-heal reverts that. Use the kill-switch
  (`lifecycle.phase: suspended`) — it drops the Pod Identity, a layer selfHeal can't heal around.

---

## Make it break — offline, no cluster

The Composition is render-tested with `crossplane render`, which needs no cluster — handy, since the hub is
parked. Try it: take the claim, set `lifecycle.phase: suspended`, and predict the render diff before you run
it. Exactly one resource changes — the `PodIdentityAssociation` vanishes (it's inside `{{- if $active }}`),
while the namespace, SA, IAM role, RolePolicy, obs-read binding, and every NetworkPolicy stay. That
single-resource diff is the kill-switch. Only the credential binding disappears, not the workload — the
whole safety argument in one render.

---

## Go deeper

- **Back to the journey:** the [agentic orientation](orientation.md), and its sibling deep dives —
  [bounding the agent](deep-dive-bounding-the-agent.md) (the identity/network/data safety in full) and
  [the triage copilot](deep-dive-the-triage-copilot.md) (the one live agent, end to end).
- **Source of truth (ADRs):** [ADR-082](../../adrs/082-platform-agent-runtime-xagent.md) (this runtime),
  [ADR-081](../../adrs/081-platform-service-delivery.md) (the supply-chain/runtime split it resolves),
  [ADR-074](../../adrs/074-agentic-workloads-platform.md) (agents as a governed workload class).
- **The code:**
  [`xagent-xrd.yaml`](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-api/templates/xagent-xrd.yaml),
  [`files/composition.yaml`](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-api/files/composition.yaml),
  [`agents.tf`](https://github.com/asanexample/platform/blob/main/infra/modules/argocd-apps/agents.tf),
  [`validate-agents.sh`](https://github.com/asanexample/platform/blob/main/.github/scripts/gitops-gate/validate-agents.sh),
  and the claim itself,
  [`gitops/agents/triage-copilot.yaml`](https://github.com/asanexample/platform/blob/main/gitops/agents/triage-copilot.yaml).
  For authoring one, the `authoring-platform-agents` house skill.
- **Substrate docs** (version-tagged — we run Crossplane v2, cluster-scoped composites; v1 "claim"
  tutorials teach a wrong model here): [Crossplane Compositions](https://docs.crossplane.io/latest/composition/compositions/)
  (~15 min) · [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
  (~10 min) · [Cilium DNS-based (`toFQDNs`) policy](https://docs.cilium.io/en/stable/security/policy/language/#dns-based)
  (~10 min).
