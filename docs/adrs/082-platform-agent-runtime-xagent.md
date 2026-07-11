# ADR-082: The `XAgent` Platform-Agent Runtime — a First-Class, GitOps-Native Agent Control Plane

**Status:** Accepted (2026-06-25) — built + live (2026-06-26)

> **Amendment (2026-06-26, epic #718):** Built and live. The triage agent (`XAgent` #1) autonomously triages
> real incidents → confident root-cause hypotheses (logs + metrics + change-correlation) → Slack, and is
> multi-cluster-aware. The cross-cluster *reach* (D2) was refined: it needs **no** cross-cluster k8s auth —
> ArgoCD on the hub already records every cluster's deploys, so the "what changed" signal is hub-local. See
> **Implementation status & learnings** below.

## Context

[ADR-074](074-agentic-workloads-platform.md) committed the platform to agents as a first-class, governed workload class and
recorded — as *direction, re-decided before build* — that an agent is "a declarative, Kyverno-governed, git-native spec…
reconciled into a running workload (mechanism — a Crossplane `XAgent` composite vs an operator-reconciled CRD — is an
implementation choice; **the composite shape is favored for consistency with `XEnvironment`**)." [ADR-080](080-triage-copilot.md)
then built the first real agent — the triage copilot — and its D3 placed it squarely as **platform infrastructure: "running
on the platform cluster… outside the per-Product Kyverno envelope / environment-namespace tenant model… a platform-system
workload like the obs stack itself, not a tenant environment workload."**

[ADR-081](081-platform-service-delivery.md) then over-corrected. Reaching (rightly) for *one delivery road*, it unified not
just the supply chain but **runtime placement** too, routing the agent through the *tenant* Environment model — a `platform`
Team Product with an `XEnvironment` placed on a cluster, provisioned by the tenant Composition, governed by a "platform-trust
envelope." In practice the placement generalization (ADR-081 D2) was deferred, so the agent landed on **preprod** — a workload
cluster — where its observability (Loki/Mimir/Tempo) and trigger (Alertmanager), all **hub-resident**, are unreachable. The
agent runs but is **blind**: `LOKI_URL=loki-gateway.observability.svc` does not resolve from preprod, so it correctly abstains
on every alert. The `platformTrust` envelope — granting cluster-wide read to a thing the Environment model assumes is
namespace-isolated — is the tell that a platform-infrastructure operator-tool was forced into a tenant-app shape.

The supply-chain unification (ADR-081 D1/D4/D5 — one registry, one build→sign→promote backbone, one OIDC/ECR story) is
**correct and stays**. The mistake was conflating *supply chain* with *runtime placement*. This ADR fixes only the latter, and
in doing so realizes ADR-074's anticipated `XAgent` composite and restores ADR-080 D3's original intent.

## Decision

Build the **`XAgent` platform-agent runtime** — a first-class, **GitOps-native agent control plane**: a Crossplane **`XAgent`
XRD + Composition** (the favored composite shape from ADR-074), agent-shaped and **distinct from the tenant `XEnvironment`**,
running on the **hub** (platform cluster) where the observability and control planes already live. Deploying a platform agent
becomes **"commit a claim → it's live"**: an `XAgent` in `gitops/agents/` is admission-gated, synced by ArgoCD to the hub's
Crossplane, and reconciled into the agent's namespace + identity + RBAC — with **zero `terragrunt apply` per agent.** The
agent's *workload* still arrives through the unchanged supply chain (ADR-081), delivered by ArgoCD as a signed, promoted digest.

This is the **runtime side of ADR-074** — the concrete realization of its declarative-`Agent` direction. The triage copilot
([ADR-080](080-triage-copilot.md)) is `XAgent` #1.

**Supply chain vs. runtime — the split that resolves ADR-081.** One supply chain + registry + governance for *all* workloads
(ADR-081, kept). Runtime **forks by workload type**: a tenant → `XEnvironment` Composition on a workload cluster (unchanged,
ADR-048); a platform agent → `XAgent` Composition on the hub (this ADR). ADR-081 D2/D3 (one Composition, placement-aware, for
platform products too) is **superseded for platform agents** by this purpose-built lane.

## Design

### D1 — `XAgent` is a first-class Crossplane composite

A new `agent-api` Helm chart (mirroring `environment-api`) installs, on the **hub's** Crossplane: an `XAgent`
CompositeResourceDefinition (`apiextensions.crossplane.io/v2`, **cluster-scoped — the `XAgent` *is* the claim**, like
`XEnvironment`; no separate claim kind) and a Pipeline Composition (`function-environment-configs` →
`function-go-templating` → `function-auto-ready`). The schema is **agent-shaped and lean**:

```yaml
spec:                         # kind: XAgent, group platform.refplat.org
  product:                    # → image/ECR/signing identity via the Product registry (supply chain unchanged)
  placement: { cluster }      # enum [platform]; default platform (hub-only for now — D2)
  model: { provider, id }     # bedrock + pinned model id → mints the bedrock IAM statement
  obsRead: bool               # bind platform-trust-observability-reader (hub obs + k8s read, no Secrets)
  access: { clusters: [] }    # clusters the agent may READ cross-cluster (D2; Phase 2)
  awsPermissions: { policyStatements: [] }   # extra IAM, deny-set validated (D5/D6)
  autonomy: { mode, maxConcurrent, tokenBudget }   # bounded autonomy (D7)
  trigger: { kind }           # informational; the alertmanager route is wired separately
  lifecycle: { phase }        # active | suspended (the kill-switch, D7)
```

It is **not** the tenant `XEnvironment` bent to fit (no quotas/tiers/stages/isolation/developer-access/`platformTrust`
envelope); it is a sibling built for agents.

### D2 — Placement: agents on the hub, reaching out by network plumbing

Platform agents **run on the hub** — that is where the data is: observability is hub-central (every spoke ships there, so the
hub holds all clusters' telemetry — ADR-044), and the control plane (ArgoCD sync history = "recent changes", the registries)
is hub-resident. A hub agent's primary inputs are therefore **in-cluster.** Live, per-cluster k8s state on *other* clusters is
reached the way Backstage already does it: a **cross-account, read-only role + `AmazonEKSViewPolicy` + the EKS API over
cross-vpc-dns/TGW** (`access.clusters`). So: *agent on the hub, assumes a scoped read role into the target cluster, reads* —
no agent placed on the workload cluster.

`placement.cluster` defaults to (and today only supports) `platform`. **Running** an agent *on* a workload cluster
(federating the `XAgent` Composition per-cluster, à la ADR-048) is a deferred extension, built only when an agent genuinely
needs to be cluster-local (real-time local watch / an admission-time actor). `access.clusters` cross-cluster *read* is
**Phase 2** (the schema lands now; the target-cluster read roles come later) — v1 triages well from hub-central obs + ArgoCD
history alone.

This is **platform agents** (operate the platform → this lane). **Tenant agents** (part of a tenant's app, owned by a product
team) remain the tenant Environment model on workload clusters — a separate, unchanged lane.

### D3 — Provisioning vs. delivery (the two-part shape, like tenants)

The **Composition provisions the slot** — namespace, named ServiceAccount, Pod Identity + IAM, obs-read RBAC, NetworkPolicy.
**ArgoCD delivers the workload** — the agent's `k8s/` manifests with the promoted, signed digest (ADR-071 templatePatch) — into
that namespace. Identical separation to the tenant model (Composition = the environment, ApplicationSet = the app), so the
supply chain (ADR-081) is preserved end-to-end: build→sign→promote→ArgoCD-deploys-to-hub.

### D4 — Bootstrapped once, then pure GitOps

The control plane (the `XAgent` XRD + Composition + the hub Crossplane's provider-kubernetes / provider-aws-iam/eks / the
functions / the provisioner identity) is installed **once** via Terragrunt — exactly as the tenant Environment control plane
was bootstrapped on preprod. After that, **adding an agent is a git commit**: an `XAgent` claim + the app repo's manifests.
"Don't rely on Terraform to deploy agents" is satisfied — the *framework* is bootstrapped once; *agents* are claims.

### D5 — Identity, authority, and the data boundary (ADR-080/074 preserved)

The Composition mints a **least-privilege EKS Pod Identity** role for the agent: the `model`→`bedrock:InvokeModel` statement
plus any `awsPermissions.policyStatements`, **deny-set validated** (ADR-062 §4 — `iam`/`sts`/`organizations`/`account`/bare-`*`
rejected) and **permissions-boundary-capped** at runtime. `obsRead` binds the agent SA to a fixed
**`platform-trust-observability-reader`** ClusterRole — read-only pods/events/apps cluster-wide, **Secrets excluded** (secret
*values* never enter the agent, never the model context). The agent stays **read-only + propose-only** (no write/exec/
remediation; egress only to Bedrock + the incident channel) — the lethal-trifecta defense of ADR-080 D4/D5 holds **because the
runtime adds zero write capability.** A cluster-wide obs-read does mean the agent sees all hub platform-infra state; that is
bounded (no Secrets, read-only) and may be namespace-scoped in a later refinement.

### D6 — Admission gate (the safety invariants made un-bypassable)

ADR-074's "safety invariants are not configurable" needs an enforcement surface; here it is, on the hub:

- **Kyverno `restrict-agent-envelope`** ClusterPolicy (an `agent-policies` chart, mirroring `restrict-environment-envelope`):
  validates ownership, `placement`, the `awsPermissions` deny-set, and that `obsRead`/`model` resolve to the *fixed* blessed
  profiles — a claim cannot mint escalation.
- **CI `validate-agents.sh`** gitops-Gate validator (mirroring `validate-environments.sh`): shape/hygiene plus the same
  deny-set and composition-render, shift-left.
- **`CODEOWNERS` for `gitops/agents/`**: authoring an agent grants cluster-read + Bedrock, so it is **admin/platform-gated** at
  the PR (author ≠ approver for privileged change, ADR-074).
- **cosign verification on the hub**: because the agent's image is now admitted on the hub, `verify-images-product` /
  `verify-attestations-product` for the agent's Product are derived into the **hub** policy unit — the signed-image guarantee
  follows the workload to the hub.

### D7 — Bounded autonomy and a kill-switch that actually stops the agent

The Composition owns scaffolding; ArgoCD owns the Deployment (selfHeal would revert a naïve `kubectl scale 0`). So
`lifecycle.phase: suspended` is enforced where it bites: the **Composition removes the Pod Identity association** (a hard stop
— no Bedrock, the agent can't reason) and the **Alertmanager route drops the agent** (no triggers). `autonomy.{maxConcurrent,
tokenBudget}` carries ADR-080 D9's storm controls. The trigger is a **curated** Alertmanager route (a `triage: enabled` /
severity match), never a catch-all — alert-storm cost + noise are bounded by construction.

### D8 — Security posture of the lane itself

- **ArgoCD gains write to the hub** (the cluster it runs on) — new blast radius. Bounded by a **tight AppProject**: only the
  agent namespace(s), `namespaceResourceWhitelist` = Deployment/Service/ExternalSecret/ConfigMap, **`clusterResourceWhitelist:
  []`** — *all* cluster-scoped identity/RBAC comes from the gated Composition, never from ArgoCD.
- **provider-kubernetes on the hub** can create ClusterRoleBindings → the `crossplane-agent-provisioner` RBAC is scoped to
  `bind` **`platform-trust-observability-reader` only**, no wildcards (passes `restrict-wildcard-rbac`).
- **Claim-driven IAM/RBAC** shifts the change-control from a Terraform plan to *the claim PR (CODEOWNERS + the Gate) + the
  deny-set + the fixed profiles* — acceptable because only `awsPermissions` is free-form and it is deny-set-capped.
- **Org SCP broadening (recorded here):** the cross-region Bedrock inference profile (`us.anthropic.claude-sonnet-4-6`) routes
  across us-east-1/2 + us-west-2, so the org `deny-regions` SCP's `NotAction` was extended with the Bedrock **data-plane**
  actions (`bedrock:InvokeModel*`, `bedrock:Converse*`) — invoke allowed in any region for all principals; Bedrock *management*
  actions stay region-pinned. A deliberate, scoped broadening, documented so it is a decision and not a silent SCP edit.

### D9 — Shared scaffolding; `XPlatformService` deferred

The ns + SA + Pod-Identity + RBAC go-template is written as a **reusable partial**, so a future generic `XPlatformService` (for
non-agent platform apps/services — backstage et al.) is a cheap follow-on: the same scaffolding with no agent layer. It is
**not built now** — there is no non-agent consumer, and building it speculatively is the over-engineering ADR-074's "pulled by
the second real agent" principle warns against. Existing Terragrunt-deployed platform apps stay as-is until one wants the lane.

> **Note (2026-07-11, [ADR-081 amendment](081-platform-service-delivery.md#amendment-2026-07-11-platform-service-placement--realizing-d2d3d6)).**
> The deferred `XPlatformService` is **not** built as a new kind. When a non-agent consumer arrived (the feature-flag service,
> [ADR-099](099-feature-flags-platform-service.md)), it proved to be *Environment-shaped* (stages, promotion, self-service AWS),
> so the non-agent lane is the **placement-aware `XEnvironment`** (a selected `environment-platform` composition), not a lean new
> composite. This D9 partial is exactly what that composition reuses — the *scaffolding* anticipated here stands; the
> *separate-kind vehicle* is superseded.

### D10 — Consistency with ADR-048

ADR-048 keeps the hub free of the **tenant Environment** Composition (to avoid multi-cluster tenant orchestration + fragile
remote provider creds). The `XAgent` Composition is a **different** Composition: it provisions **hub-local, in-cluster**
platform infra via `InjectedIdentity` provider-kubernetes — no remote creds, no cross-cluster tenant orchestration. The hub
already runs platform infra (argocd, backstage, the obs stack); a hub-local agent Composition is **more platform infra on the
hub**, fully consistent with ADR-048's intent. Tenants still run only on workload clusters.

## Scope

- **In:** the `agent-api` chart (`XAgent` XRD + Composition + `agent-policies` + the obs-read ClusterRole); the one-time hub
  control-plane bootstrap; the `gitops/agents/` claim-sync + ArgoCD hub registration; the platform-agent workload ApplicationSet
  - the tight AppProject; the triage copilot re-expressed as `XAgent` #1 and migrated off preprod; the curated Alertmanager
  trigger + kill-switch.
- **Out (for now):** `XPlatformService` (non-agent platform workloads); running an agent *on* a workload cluster (per-cluster
  `XAgent` federation); `access.clusters` cross-cluster read roles (Phase 2); migrating backstage/argocd/obs onto the lane.

## Consequences

- **Deploying a platform agent is a git commit** — the ADR-074 declarative-`Agent` vision, realized; agent #2..N are claims,
  not new infra.
- **ADR-080 D3 is restored** (platform-system, hub-placed, outside the tenant model) and the agent is finally **un-blinded** —
  its hub-in-cluster obs endpoints resolve.
- **ADR-081's supply-chain unification stands**; only its runtime-placement generalization is superseded for platform agents.
- **Real new surface to own and operate carefully:** a second Crossplane control plane on the hub (version-skew vs. the tenant
  `environment-api` — a *different* chart, pinned), the claim-driven IAM/RBAC change-control shift, and ArgoCD's new hub-write
  blast radius — each mitigated above, none free.
- **This is a sizeable, initially-unproven build for one agent.** Mitigated by validating the Composition with `crossplane
  render` before any apply and **keeping the preprod agent alive (abstaining is harmless) as fallback until the hub `XAgent`
  verifiably triages** — no cut-over on faith.

## Implementation status & learnings (2026-06-26)

Built and live (epic #718). The agent autonomously triages real incidents to confident hypotheses on
**logs + metrics + change-correlation**, posted to the incident channel, multi-cluster-aware.

**What shipped beyond the core Composition:** the Mimir **ruler** (P4 — so a spoke/preprod alert can fire
and reach the agent at all, vs. only the hub Prometheus's locally-scraped metrics); the
**`get_recent_changes`** change-correlation tool (ADR-080 D2 — it had been planned but never registered, so
the agent's strongest heuristic was inert and it abstained on every alert); per-tool **gather logging**
(OTel traces can be network-blocked, so stdout is the real debugging surface); **tenant-aware obs** (the
`X-Scope-OrgID` follows the alert's `cluster` label); and **ArgoCD as the cross-cluster change source**.

**Cross-cluster reach (D2), refined — no cross-cluster k8s auth needed.** The plan had the agent read
*preprod's* k8s API for "what changed" (cross-account IAM + an EKS access entry + a network path).
Unnecessary: **ArgoCD runs on the hub and records deploys for every managed cluster**, so
`get_recent_changes` reads ArgoCD hub-local for the change timeline and the obs tenant follows the alert's
cluster. A preprod incident gets its full picture (symptom + logs/metrics + change) without the agent ever
touching preprod's API. The deferred `access.clusters` cross-cluster *k8s* read is thus off the critical path.

**Durable agent-infra learnings — the theme is RBAC ≠ reachability.** A hub-resident agent needs explicit
network + identity wiring that tenant workloads inherit for free:

- **SA token must be explicitly mounted.** `get_recent_changes` reads the k8s API, but Kyverno's
  `mutate-automount` stamps `automountServiceAccountToken=false` when absent — leaving only the Pod-Identity
  (Bedrock) token. Fix = `automountServiceAccountToken: true` **and** excluding `runtime=platform-agent` from
  the `restrict-automount-sa-token` policy.
- **The observability namespace default-denies ingress** — obs-read RBAC grants *what* the agent may read,
  not *whether it can connect*. Needs a NetworkPolicy admitting `runtime=platform-agent` to the obs stores.
- **The gitops Release gate had to learn a Release can target an `XAgent`**, not only an `XEnvironment` —
  else every agent image promote fails the sibling-claim check.
- **Cilium: a k8s `ipBlock` egress NetworkPolicy does not cover in-cluster (identity-matched) or host (the
  Pod-Identity agent) traffic** — mirroring the tenant ipBlock netpol onto the agent silently blocked Bedrock
  - obs. A proper Cilium-native agent egress policy shipped since (identity/entity-based, not ipBlock — see below).
- **ArgoCD won't auto-retry a sync that failed and exhausted its retries on the same revision**; fixing a
  *different* resource doesn't unstick it — trigger the sync explicitly.

**Correction (record-keeping):** an earlier working note claimed manifest-only app changes need a rebuild
because the workload ApplicationSet pins manifests to the Release commit. That is wrong — the ApplicationSet
sources manifests at **`targetRevision: HEAD`**; only the image **digest** is Release-pinned ([ADR-071](071-digest-promotion-via-control-plane.md)).
A manifest-only change delivers on the next sync with no rebuild (platform#739 additionally added a
`deploy.yml` path-filter so such commits don't even trigger CI).

**Shipped since (2026-06-26):** both follow-ups landed — the per-tenant Mimir ruler **rules-sync** (curated spoke
rules as a ConfigMap, loaded per tenant by a self-healing `mimirtool rules sync` CronJob) and the proper
Cilium-native agent **egress** policy (default-deny egress allowing DNS + `kube-apiserver` + host(Pod-Identity) +
the observability ns + `toFQDNs` Bedrock/Slack — later widened to `*.slack.com` for Socket Mode). The reference
agent (triage) also matured into a deep workload — per-failure-mode playbooks, six grounded tools, a rich card,
and a closed feedback loop over Socket Mode — recorded in [ADR-080](080-triage-copilot.md).

**Remaining follow-ups:** the eval harness as a CI **regression gate** and ADR-076 content-capture — both tracked
in [ADR-080](080-triage-copilot.md).

## Alternatives considered

- **Federate the tenant `XEnvironment` Composition to the hub** (ADR-081 D2/D3 taken to completion). Rejected: it makes the hub
  a tenant-workload-hosting cluster (against ADR-048), runs the full tenant governance machinery for things that aren't
  tenants, and keeps bending the `platformTrust` envelope around platform infra forever.
- **A Terragrunt unit per platform agent** (the Backstage pattern). Rejected: simpler to build, but every agent pays a
  `terragrunt apply` friction tax — the antithesis of "commit a claim → it's live" — and the lane would be rebuilt as an XRD
  anyway once the fleet grew.
- **Keep the agent on preprod, expose hub obs query endpoints cross-cluster.** Rejected: the obs design deliberately keeps the
  *query* path in-cluster (only the *write* path is cross-cluster); exposing query cross-cluster is a new, security-laden
  capability, and the agent is platform infra that belongs on the hub regardless.

## Related

[ADR-074](074-agentic-workloads-platform.md) (the agentic substrate — this is its runtime side; the `XAgent` composite it
favored) · [ADR-080](080-triage-copilot.md) (`XAgent` #1; D3's placement intent, restored) ·
[ADR-081](081-platform-service-delivery.md) (the supply-chain/registry unification kept; its runtime-placement decision
superseded for platform agents) · [ADR-048](048-federated-per-cluster-crossplane.md) (the tenant per-cluster control plane this
keeps intact; the agent Composition is consistent, D10) · [ADR-067](067-idp-domain-model.md) (Team→Product; Placement) ·
[ADR-071](071-digest-promotion-via-control-plane.md) (the Release-digest delivery reused) · [ADR-062](062-self-service-tenant-provisioning.md)
(the policyStatements deny-set) · [ADR-041](041-pod-identity-for-tenant-workloads.md)/[ADR-047](047-pod-identity-as-aws-identity-standard.md) (Pod Identity) ·
[ADR-014](014-kyverno-as-policy-engine.md) (the admission gate) · [ADR-076](076-agent-observability.md) (the agent-trace model).
Epic: #554 (agentic) / #102 (observability).
