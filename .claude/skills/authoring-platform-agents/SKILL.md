---
name: authoring-platform-agents
description: >-
  How to author and operate a platform agent on this platform — the GitOps-native XAgent
  control plane (ADR-082). Use when adding a new platform agent, editing an XAgent claim in
  gitops/agents/, wiring an agent's model/obsRead/awsPermissions/autonomy/trigger, using the
  lifecycle kill-switch, or reasoning about what the gitops Gate (validate-agents.sh) and
  Kyverno (restrict-agent-envelope / restrict-agent-control-plane) will reject. Covers the
  XAgent claim shape and its real spec fields, where claims live, the Product/supply-chain join,
  the Composition-provisions-vs-ArgoCD-delivers split, and the hub-only placement. The reference
  agent is the triage copilot (ADR-080). NOT for the tenant XEnvironment claim
  (environment-onboarding) or the Composition internals (crossplane-composition-authoring); NOT
  for operating a live agent day-2 (docs/runbooks/agent-operations.md). There is NO scaffolder
  template — authoring is editing the gitops/agents/ registry by hand.
---

# Authoring platform agents (`XAgent`)

A **platform agent** is a first-class, governed workload that operates the platform (e.g. the triage
copilot that root-causes incidents). It is **not** a tenant app. The runtime is the **`XAgent`**
control plane ([ADR-082](../../../docs/adrs/082-platform-agent-runtime-xagent.md)) — the realization of
[ADR-074](../../../docs/adrs/074-agentic-workloads-platform.md)'s declarative-`Agent` direction. Adding
an agent is **"commit a claim → it's live"**: an `XAgent` in `gitops/agents/` is admission-gated, synced
by ArgoCD onto the **hub** (platform cluster) Crossplane, and reconciled into the agent's runtime slot —
**zero `terragrunt apply` per agent**.

> The reference agent is **`triage-copilot`** ([ADR-080](../../../docs/adrs/080-triage-copilot.md)) —
> `XAgent` #1, live + autonomous on the hub. Read `gitops/agents/triage-copilot.yaml` as the worked example.
> **There is no `new-agent` scaffolder** — you author the claim by hand.

## The two-part shape (like tenants)

Provisioning and delivery are **separate**, exactly as for a tenant environment:

- **The Composition provisions the slot** — namespace `platform-agent-<name>`, a named ServiceAccount, an
  EKS **Pod Identity** role (the model's Bedrock grant + any `awsPermissions`), the obs-read RBAC binding
  (when `obsRead`), and the ingress/egress NetworkPolicies. Source:
  `infra/modules/crossplane/charts/agent-api/files/composition.yaml`.
- **ArgoCD delivers the workload** — the agent's `k8s/` manifests with the promoted, **signed** image digest
  (ADR-071), into that namespace, via the per-agent ApplicationSet (`infra/modules/argocd-apps/agents.tf`).

So your `XAgent` claim provisions the slot; the agent's **app repo** (its Product) ships the Deployment.
Authoring an agent therefore touches **two** places: the claim here, and the app's manifests/CI in its repo
(supply chain unchanged — see the `supply-chain-onboarding` skill).

## Where claims live

```text
gitops/agents/<name>.yaml      # one XAgent per file; <name> → namespace platform-agent-<name>, SA + role named from it
gitops/agents/README.md        # the registry README
```

The `agents` registry-sync Application projects `gitops/agents/*.yaml` onto the hub's `crossplane-system`
(ADR-082; `argocd-apps/agents.tf`). **CODEOWNERS-gated** — authoring an agent grants cluster-read + Bedrock,
so the PR is admin/platform-reviewed (author ≠ approver for a privileged change, ADR-074).

## The `XAgent` claim — real spec fields

Verified against the XRD `infra/modules/crossplane/charts/agent-api/templates/xagent-xrd.yaml`
(`apiextensions.crossplane.io/v2`, **cluster-scoped** — the `XAgent` *is* the claim, like `XEnvironment`;
there is no separate claim kind). The schema is deliberately **lean** — it is **not** the tenant
`XEnvironment` (no quotas/tiers/stages/isolation/developer-access/domains).

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata:
  name: triage-copilot          # → namespace platform-agent-triage-copilot; SA + Pod-Identity role named from it
spec:
  team: platform                # REQUIRED. Owning Team — join key to the Product registry + the Release path
  product: triage-copilot       # REQUIRED. Owning Product (gitops/products/<team>/<product>.yaml) — image/ECR/signing
  placement:
    cluster: platform           # enum [platform] only; default platform. Hub-only today (ADR-082 D2)
  model:
    provider: bedrock           # enum [bedrock, none]; default bedrock
    id: us.anthropic.claude-sonnet-4-6   # PINNED model/inference-profile id (no floating model, ADR-074)
  obsRead: true                 # bind platform-trust-observability-reader (cluster-wide READ, NO Secrets); default false
  access:
    clusters: []                # cross-cluster READ targets — DEFERRED, Phase 2 (schema lands now, roles later)
  awsPermissions:
    policyStatements: []        # extra IAM beyond the model grant; deny-set validated (default empty)
  autonomy:
    mode: propose-only          # enum [propose-only] only — the safety invariant (read + propose, never act)
    maxConcurrent: 4            # runner concurrency cap (storm control); informational to the Composition
    tokenBudget: "..."          # rolling token/cost budget (circuit breaker); informational
  trigger:
    kind: alertmanager-webhook  # enum [alertmanager-webhook, schedule, manual]; informational — route wired separately
  lifecycle:
    phase: active               # enum [active, suspended]; default active. `suspended` = the kill-switch
```

Only `spec.team` and `spec.product` are **required**; everything else has a schema default. A minimal
obs-read triage-style agent is essentially the `triage-copilot.yaml` shown above.

### Field notes (what each one actually does)

- **`team` + `product`** — the join into the **Product registry** (`gitops/products/<team>/<product>.yaml`).
  That entry's `spec.repo` is the app repo; the image scope is `team-<team>/<product>-<svc>`; the signed
  digest is read from `gitops/releases/<team>/<product>/`. The supply chain is **unchanged** from tenants
  (ADR-081). The owning Product **must exist** (the gate checks it) and its `spec.team` must match.
- **`placement.cluster`** — `platform` only (hub). Running an agent *on* a workload cluster is a deferred
  extension (ADR-082 D2); don't set anything else — the XRD enum and the gate both reject it.
- **`model`** — mints a least-privilege **Bedrock data-plane** grant (`bedrock:InvokeModel*` / `Converse*`,
  invoke/converse only, never management) onto the agent's Pod-Identity role. The id is **pinned** — a model
  change is a new release. `us.*` ids are cross-region inference profiles (ADR-082 D8).
- **`obsRead`** — binds the agent's SA to the fixed, platform-provided **`platform-trust-observability-reader`**
  ClusterRole: cluster-wide read of pods/events/services/deployments + ArgoCD `Applications` + the `Product`
  registry. **Secrets are excluded** (secret values never enter the agent / the model context). You bind it;
  you cannot redefine what it grants.
- **`awsPermissions.policyStatements`** — extra IAM attached to the Pod-Identity role, **deny-set validated**
  (see below) and permissions-boundary-capped at runtime. Leave empty for an obs-read-only agent.
- **`autonomy.mode`** — `propose-only` is the only mode (the ADR-074 safety invariant: read + propose, never
  act). `maxConcurrent` / `tokenBudget` are storm/cost controls — informational to the Composition, enforced
  by the agent itself.
- **`trigger.kind`** — informational metadata; the actual Alertmanager route is wired **separately** (ADR-082
  Phase 5), not by the claim.
- **`lifecycle.phase`** — the **kill-switch** (see below).

## The supply-chain / Product join (do this first)

Before the agent runs you need a **Product** for it. For a platform agent that's a `platform`-team Product —
e.g. `gitops/products/platform/triage-copilot.yaml` (`spec.team: platform`, `spec.repo: <org>/<app-repo>`).
The agent's image must be **cosign-signed + attested** and promoted as a digest into
`gitops/releases/<team>/<product>/` — because the image is admitted **on the hub**, the platform-owned
`verify-images-product` / `verify-attestations-product` for the agent's Product are derived into the **hub**
policy unit (ADR-082 D6). Wire the app repo's CI exactly like any product (the `supply-chain-onboarding` skill).

## What the gate + Kyverno will reject

**`validate-agents.sh`** (`.github/scripts/gitops-gate/`) — the **shift-left** gate, run on the PR:

- `kind` must be `XAgent`; `spec.team` and `spec.product` are required.
- `spec.placement.cluster` must be `platform` (absent → default `platform`, OK).
- a `bedrock` agent must pin `spec.model.id` (no floating model).
- the owning Product `gitops/products/<team>/<product>.yaml` must exist and its `spec.team` must match.
- the **IAM deny-set**: no `awsPermissions` action in the services `iam`, `sts`, `organizations`, `account`,
  and no bare `*` (ADR-062 §4). This is the same escalation guard as tenants — agents get **no exception**.

**Kyverno on the hub** (`agent-policies` chart, **Enforce** from day one):

- **`restrict-agent-envelope`** — re-enforces the `awsPermissions` deny-set (per-action `foreach` deny) and
  `placement` hub-only at admission. The free-form risk is `awsPermissions`; `placement`/`model`/`autonomy`
  are XRD-enum-constrained.
- **`restrict-agent-control-plane`** — `XAgent` claims may be authored **only by platform principals**
  (GitOps / the deployer), never ad-hoc. (Defense-in-depth: `XAgent` is cluster-scoped, so a caller already
  needs cluster RBAC, and `gitops/agents/` is CODEOWNERS-gated.)

The XRD enums are the primary guard (`provider`, `placement.cluster`, `autonomy.mode`, `lifecycle.phase`),
the gate is shift-left, and Kyverno is the un-bypassable admission backstop — three layers, by design (ADR-082 D6).

## The kill-switch — `lifecycle.phase: suspended`

Flip `spec.lifecycle.phase` to `suspended` and commit. The Composition **removes the Pod Identity
association** — a hard stop: no Bedrock, the agent can't reason. It's selfHeal-proof: ArgoCD keeps the
Deployment running but the agent is **defanged** (the kill-switch bites at the Composition layer, not the
Deployment, because ArgoCD owns the Deployment and would revert a naïve `kubectl scale 0`). Flip back to
`active` to restore. Operational detail: `docs/runbooks/agent-operations.md`.

## Delivery vs. provisioning (don't confuse them)

- The **`agents` registry-sync** Application syncs your claim → the hub Crossplane → the **Composition**
  provisions the slot. This is **provisioning**.
- The **per-agent ApplicationSet** (`agent-<name>`, in `agents.tf`) fans out over the agent's Product
  Release records and delivers the **signed image digest** into the slot. This is **delivery**. Its
  AppProject is tight — `clusterResourceWhitelist: []`, namespaced kinds only — so **all** cluster-scoped
  identity/RBAC comes from the gated Composition, never from ArgoCD (the hub-write blast radius, ADR-082 D8).
  Both target the **hub** (`var.hub_cluster_server`), unlike tenant delivery which targets the workload cluster.

A manifest-only change to the app repo delivers on the next sync at `targetRevision: HEAD` (no rebuild); only
the image **digest** is Release-pinned (ADR-071, corrected in ADR-082's learnings).

## Gotchas (from the live build — ADR-082 learnings)

A hub-resident agent needs explicit wiring that tenant workloads inherit for free:

- **SA token must be explicitly mounted** if the agent reads the k8s API — set
  `automountServiceAccountToken: true` on the pod **and** exclude `runtime=platform-agent` from the
  automount policy (Kyverno otherwise stamps it `false`). The Composition labels the namespace
  `platform.refplat.org/runtime: platform-agent` for exactly this kind of match.
- **The observability namespace default-denies ingress** — obs-read RBAC grants *what* the agent may read,
  not *whether it can connect*; the Composition ships the egress CiliumNetworkPolicy (DNS + kube-apiserver +
  host/Pod-Identity + the obs ns + `toFQDNs` Bedrock/Slack/GitHub) and the cluster-rbac unit admits the agent
  to the obs stores. A k8s `ipBlock` egress policy does **not** cover in-cluster (identity-matched) or host
  (Pod-Identity) traffic on Cilium — that's why egress is Cilium-native.
- **The gitops Release gate learned a Release can target an `XAgent`**, not only an `XEnvironment` — else the
  image promote fails the sibling-claim check.

## References

- [ADR-082](../../../docs/adrs/082-platform-agent-runtime-xagent.md) — the `XAgent` runtime (this skill's spine)
- [ADR-080](../../../docs/adrs/080-triage-copilot.md) — the reference agent · [ADR-074](../../../docs/adrs/074-agentic-workloads-platform.md) — the agentic substrate / safety invariants
- `gitops/agents/README.md` + `gitops/agents/triage-copilot.yaml` — the registry + worked example
- `infra/modules/crossplane/charts/agent-api/` (XRD + Composition + obs-reader ClusterRole) and `.../agent-policies/` (the admission policies) — both have a README
- `infra/modules/argocd-apps/agents.tf` — the registry-sync + per-agent ApplicationSet
- `.github/scripts/gitops-gate/validate-agents.sh` — the shift-left gate
- `docs/runbooks/agent-operations.md` — operating a live agent (deploy/observe/suspend)
