# Learn: The Agentic Platform — reference

Look-up, not a lesson. Build the model in the [orientation](orientation.md) first. Verified against code +
ADRs + git history (the hub cluster was parked at write time, so live-status rests on the ADR "built+live"
headers, the committed claim, and the continuous promote commits — not a fresh `kubectl`).

## The ADR map

| ADR | What | Status |
| --- | --- | --- |
| **[074](../../adrs/074-agentic-workloads-platform.md)** | The thesis — agents as a governed workload class (run/govern/secure); extends the existing moat | Proposed (spine committed) |
| **[082](../../adrs/082-platform-agent-runtime-xagent.md)** | The `XAgent` runtime — XRD + Composition on the hub | **Accepted, built+live** |
| **[080](../../adrs/080-triage-copilot.md)** | The first/reference agent — the triage copilot | **Accepted, built+live** |
| **[084](../../adrs/084-platform-identity-directory-and-owner-resolution.md)** | Owner resolution + directory (triage → owning team) | Proposed; team-floor + PagerDuty live |
| **[076](../../adrs/076-agent-observability.md)** | Agent/GenAI observability (see the Observability module) | Accepted, slices 1–3 live |
| **[086](../../adrs/086-autonomous-agent-access.md)** | The autonomy ladder — graduated, eval-gated autonomy | **Proposed (sketch); only capture built** |
| **[075](../../adrs/075-resource-agent.md)** | The resource agent (2nd, NL self-service) | Proposed, **not built** (#554) |
| **[081](../../adrs/081-platform-service-delivery.md)** | Platform-service delivery — one supply chain, runtime forks by type | Proposed; supply-chain half stands |

**The rule that emerged (082 vs 081):** *one supply chain for everyone; runtime forks by workload type* —
tenant → `XEnvironment` on a workload cluster; platform agent → `XAgent` on the hub.

## The `XAgent` (the claim) — [ADR-082](../../adrs/082-platform-agent-runtime-xagent.md)

`XAgent` : agent :: `XEnvironment` : tenant. Crossplane composite, **cluster-scoped** (the claim *is* the XR;
authoring needs cluster RBAC — the first gate), group `platform.refplat.org/v1beta1`, hub-only. Chart:
`infra/modules/crossplane/charts/agent-api/`. Claim: `gitops/agents/triage-copilot.yaml` (the only one today).

**Spec fields:** `team`+`product` (required, → Product registry, ECR scope, signing) · `placement.cluster`
(enum `["platform"]`) · `model.{provider,id}` (`bedrock`|`none`; **pinned** model id, e.g.
`us.anthropic.claude-sonnet-4-6`) · `obsRead` (bool → binds the read-only `platform-trust-observability-reader` ClusterRole)
· `access.clusters` (cross-cluster read — schema only, roles Phase 2) · `awsPermissions.policyStatements`
(extra IAM, **deny-set validated** + boundary-capped) · `autonomy.{mode,maxConcurrent,tokenBudget}`
(`mode` enum = **`propose-only`** only) · `trigger.kind` (informational) · `lifecycle.phase`
(`active`|`suspended` — the kill-switch). `status`: `namespace`, `roleArn` (outputs, never authored).

**Composition** (`files/composition.yaml`, Pipeline mode: `function-environment-configs` →
`function-go-templating` → `function-auto-ready` — same 3-function pattern as the tenant Composition; shipped
via `.Files.Get` so Helm `{{}}` doesn't eat Crossplane `{{}}`). Provisions the **slot**: namespace
`platform-agent-<name>` (PSA baseline/restricted) · ServiceAccount · IAM role `Pod-platform-agent-<name>`
(trust `pods.eks.amazonaws.com`, `AssumeRole`+`TagSession`, boundary-capped) · RolePolicy (Bedrock
invoke/converse **only**, on `foundation-model/*`+`inference-profile/*`) · **PodIdentityAssociation (rendered
only when `active` — the kill-switch)** · obs-read ClusterRoleBinding (to the *named* SA) · NetworkPolicies.
**Not rendered by the Composition:** the agent Deployment/Service + its `/metrics` ServiceMonitor — those are
ArgoCD's job (the provisioning ⟂ delivery split).

## The GitOps control plane

`gitops/agents/*.yaml` → an ArgoCD **registry-sync** Application (AppProject whitelists *only* `XAgent`
cluster resources) syncs claims to the hub Crossplane → Composition reconciles the slot. A **per-agent
workload ApplicationSet** (`agent-<name>`) fans out over the agent's `Release` records
(`gitops/releases/<team>/<product>/*.yaml`, promoted signed **digest**, ADR-071) and delivers the workload
into the slot (its AppProject: `clusterResourceWhitelist: []` — no cluster writes ever). Bootstrap:
`enable_agent_api = true` on the hub crossplane unit → after that, **adding an agent is a git commit** (no
per-agent apply). Delivery wiring: `infra/modules/argocd-apps/agents.tf`.

## Bounding the agent (all built) — [deep dive](deep-dive-bounding-the-agent.md)

- **Identity:** named SA + **EKS Pod Identity** (keyless). IAM = Bedrock **invoke** only + deny-set-validated
  extras + permissions boundary. In-cluster = **read-only** `platform-trust-observability-reader` ClusterRole (pods/events/
  apps/argocd-apps/products registry) — **Secrets excluded**; the agent can be *bound* to it, never *redefine*
  it. **No write/exec/remediation verb** anywhere.
- **Propose-only** by *absence of capability* — the single write is posting to the incident surface.
- **Network default-deny both ways:** ingress only from `observability`/`kube-system` (the trigger, :8080);
  egress (**CiliumNetworkPolicy**, not a k8s ipBlock — in-cluster dests are identity-matched, the Pod-Identity
  agent is host-local) only to DNS + kube-apiserver + host (creds) + `observability`/`platform-directory`/
  `keycloak` + `toFQDNs` Bedrock/`*.slack.com`/`api.github.com`.
- **Data boundary** ([ADR-076](../../adrs/076-agent-observability.md)): metadata always; raw content
  redacted per compliance tier, never to a SaaS; **secrets in context = hard never**; regulated tiers
  metadata-only.
- **Kill-switch** (`lifecycle.phase: suspended`): Composition drops the **PodIdentityAssociation** → no
  Bedrock → can't reason. Bites at a layer GitOps can't heal around (not the Deployment). Fixture:
  `.agent-api-tests/agents/triage-copilot-suspended.yaml`.
- **Admission (3 layers):** XRD enums (provider/placement/autonomy/lifecycle) · the CI gate
  `validate-agents.sh` (shift-left deny-set + hub-only + pinned model + owning Product) · hub **Kyverno**
  `restrict-agent-envelope` + `restrict-agent-control-plane` (only platform principals may author `XAgent`s).
  Plus **CODEOWNERS-gated** authoring (author ≠ approver — authoring grants cluster-read + Bedrock).

## Autonomy ladder (designed only) — [ADR-086](../../adrs/086-autonomous-agent-access.md) / [deep dive](deep-dive-autonomy-and-evaluation.md)

Graduated, **per-action-class**, earned, machine-bounded: **shadow** (proposes; system records what it *would*
have done + whether right) → eval scores vs a per-tier bar → **promoted** to autonomous on that class →
**auto-demoted on regression**. Irreversible/unbounded classes → *never* autonomous (a reversibility
registry). *"More permissive" = move the guardrail human→machine, not remove it.*

**Status:** `autonomy.mode` **schema-locked to `propose-only`** (the API can't express autonomy). Grader,
reversibility registry, action-time policy engine = **unbuilt**; gated on **eval-as-a-service** (doesn't
exist). **Built:** the *forward-capture substrate* (#1074) — `infra/modules/aws/agent-eval-store/` → S3
`platform-agent-eval-corpus` (write-once, TLS-only, versioned, SSE-S3→CMK by cost profile), capturing real
triage episodes `{alert-group, snapshot, label, rubric}`. The agent's write grant is on *its own claim*
(avoids a chicken-and-egg on the composed role ARN). *"Build the pipeline, not the corpus; the examiner
doesn't exist yet."*

## The triage copilot (the one live agent) — [ADR-080](../../adrs/080-triage-copilot.md) / [deep dive](deep-dive-the-triage-copilot.md)

**Job:** shorten "alert fired" → "human knows where to look + who owns it." **Loop:** Alertmanager webhook
(triages the alert *group*, not each alert) → scope → **read-only** evidence (Mimir/Loki/Tempo/k8s) →
**change-correlation** (the PR whose rollout window straddles the alert + the scoped diff — highest yield) →
ranked hypotheses w/ evidence deep-links → **resolveOwner** → post a **triage card** (summary · hypotheses+
confidence · next *diagnostic* step, never a fix · `disposition` ∈ confident-lead/weak-leads/insufficient-
evidence). Below a confidence floor: **abstain + page a human** (a confident-wrong RCA scores worse than an
abstain). **Autonomously triggered, strictly propose-only in action.**

**Owner-routing** ([ADR-084](../../adrs/084-platform-identity-directory-and-owner-resolution.md)):
`resolveOwner({namespace, culpritLogin?})` reads the **git registries** (namespace→Product→Team; the agent is
a *consumer*, not a control plane) → facts only; `applyMentionPolicy(resolved, {severity,disposition})`
decides the ping (author → team on-call → user-group → channel → plain text). An **@mention fires only** at a
trusted tier AND confident-lead + critical. **Team is the resolution floor** (works day one). Split so a
directory bug can't misfire a page.

**Eval loop:** the triage card's **accept/correct/dismiss** buttons → `triage_feedback_total{verdict,disposition}`
→ accept-rate *by disposition* (calibration) + the eval corpus. **Observed:** the "Triage Agent (ADR-076)"
dashboard — see the [Observability agent-obs deep dive](../observability/deep-dive-agent-observability.md)
(don't re-teach). *Impl note:* the agent loop's Go source is in the app repo (`platform-triage-copilot`), not
this infra repo — this repo defines the claim, runtime, directory backend, and observability.

## Status ledger

- **LIVE:** `XAgent` runtime (082), triage copilot (080, propose-only, continuously promoted), agent-obs
  (076 slices 1–3), the bounding machinery (identity/envelope/kill-switch/netpol/data-boundary/admission),
  owner-routing team-floor + PagerDuty on-call (084 Phase 0/2), the eval **capture** substrate (#1074).
- **Designed / not built:** the **autonomy ladder** enforcement (086 — grader, registry, policy engine);
  **eval-as-a-service**; the **resource agent** (075, epic #554); full person-level identity linking (084
  Phase 1/3); cross-cluster `access.clusters` roles.
- **Deferred:** multi-agent / agent-to-agent (A2A); full content-capture w/ redaction; self-hosted Langfuse;
  a model gateway; the FinOps agent (ADR-092 D7); a generic `XPlatformService` lane.

## Gotchas

- **Autonomously *triggered* ≠ autonomous *action*.** The one live agent only proposes.
- **RBAC ≠ reachability** — a hub agent needs explicit *network* wiring (obs egress + trigger ingress); a read
  grant doesn't open the path.
- **Cilium egress, not a k8s `ipBlock`** — in-cluster dests are identity-matched, creds are host-local; a
  tenant-style ipBlock silently blocks Bedrock.
- **Kill-switch bites the Pod Identity, not the Deployment** — `kubectl scale 0` gets healed by ArgoCD;
  suspend removes the *capability*.
- **`obsRead` grants read with NO Secrets** — a fixed platform-owned role a claim can't widen.
- **A hub agent is a single instance** — one active Release; a second → a duplicate Application (fail-loud).

## Go deeper

Deep dives: [the XAgent runtime](deep-dive-the-xagent-runtime.md) ·
[bounding the agent](deep-dive-bounding-the-agent.md) · [autonomy & evaluation](deep-dive-autonomy-and-evaluation.md) ·
[the triage copilot](deep-dive-the-triage-copilot.md). Author an agent: the `authoring-platform-agents` skill.
Cross-links: [Environment API](../environment-api/orientation.md) · [Identity](../identity/orientation.md) ·
[Observability](../observability/deep-dive-agent-observability.md) · [Supply chain](../supply-chain/orientation.md).
External: [OWASP LLM/Agentic risks](https://genai.owasp.org/) ·
[NIST AI RMF](https://www.nist.gov/itl/ai-risk-management-framework) ·
[AWS Bedrock](https://docs.aws.amazon.com/bedrock/) · [OpenTelemetry GenAI](https://opentelemetry.io/docs/specs/semconv/gen-ai/).
