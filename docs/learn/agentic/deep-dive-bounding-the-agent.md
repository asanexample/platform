# Learn: The Agentic Platform — bounding the agent (deep dive)

This opens one box: *exactly how* a compromised, confused, or hijacked agent is stopped from causing
harm. For the claim → slot mechanism see the [runtime deep dive](deep-dive-the-xagent-runtime.md); for
the autonomy ladder, [autonomy & evaluation](deep-dive-autonomy-and-evaluation.md). This one is about
the cage.

## The premise

An agent is a **governed principal, not a pod.** A normal pod you bound because bugs happen. An agent
you bound because its brain is a non-deterministic model you don't control, fed untrusted input —
alerts, logs, diffs, all of it a prompt-injection surface, and every published defense against prompt
injection can be bypassed individually
([ADR-074](../../adrs/074-agentic-workloads-platform.md)). So the rule is blunt: **never trust the
model's behavior — bound its capability in advance.** A perfectly hijacked agent must still be unable
to exceed its badge.

Two images make the shape concrete. A **visitor badge** that opens only a few doors: the agent's
identity is scoped so tightly that "misbehaving" and "behaving" reach the same short list of rooms. And
an **intern with a supervisor**: it may read the building and write a memo, but every consequential
action goes to a human — not because we asked it nicely, but because it holds no key that turns. Where
both images break is judgment. A real visitor or intern has some you can lean on in a pinch; this one
doesn't, and its improvisation *is* the risk. So the bounds are hard, external to the model, and never
rely on goodwill.

The rest is six independent bounds, then the admission gates that keep them un-bypassable, then the one
idea that ties them together — the lethal trifecta — and the one place the code is leaner than the ADR.

## Bound 1 — identity: a scoped badge, keyless

The agent runs under a **named [ServiceAccount](https://kubernetes.io/docs/concepts/security/service-accounts/)**
(`triage-copilot`, from the `XAgent`'s `metadata.name`) and gets AWS credentials through
**[EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)** — the Composition
mints a `PodIdentityAssociation` binding that SA to a per-agent IAM role (`Pod-platform-agent-triage-copilot`).
Pod Identity ([ADR-041](../../adrs/041-pod-identity-for-tenant-workloads.md)/047) means **no key is
ever minted, baked into the image, or parked in a Secret to be stolen** — the pod gets short-lived SigV4
credentials at runtime, scoped to exactly what the claim declared. No long-lived secret exists whose
theft is a breach.

Its only *in-cluster* power is **read**, of a fixed, platform-owned menu. When the claim sets `obsRead: true`,
the Composition binds the agent's SA to one ClusterRole, `platform-trust-observability-reader`
(`agent-api/templates/platform-trust-cluster-roles.yaml`). Notice what's there — and what isn't:

```yaml
rules:
  - apiGroups: [""]
    resources: [pods, events, services, endpoints, nodes, namespaces, replicationcontrollers]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: [events.k8s.io]
    resources: [events]
    verbs: [get, list, watch]
  - apiGroups: [argoproj.io]        # ArgoCD sync history — the change-correlation signal
    resources: [applications]
    verbs: [get, list, watch]
  - apiGroups: [platform.refplat.org]  # the Product registry — map a namespace → its GitHub repo
    resources: [products]
    verbs: [get, list, watch]
```

Every verb is `get`/`list`/`watch`. **[Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
are deliberately absent** — secret *values* never enter the agent, never the model's context. That's not
an accident of scoping; it's platform-*owned*. The ClusterRole is labeled
`platform.refplat.org/trust: "true"`, and a claim can be bound to it but can **never redefine** what it
grants. (The admission plane below is what stops a claim from binding some other, fatter role.) The
binding names the SA specifically — not "all ServiceAccounts in the namespace" — so a stray SA that
lands in the agent's namespace inherits nothing.

The missing Secrets access is doing real work, not just tidiness. The agent's context is fed to a
non-deterministic model over an untrusted-input channel: a secret it can *read* is a secret it can be
*tricked into emitting*. Remove the capability and you remove the whole class.

## Bound 2 — least-privilege IAM: Bedrock invoke, and a deny-set

The agent's IAM role carries exactly two kinds of statement (`composition.yaml`, the `render-resources` step):

1. **The model grant — invoke only.** For a `bedrock` model with a pinned id, the Composition appends a
   single statement allowing `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`,
   `bedrock:Converse`, `bedrock:ConverseStream` — the data plane, calling the model. Never Bedrock
   *management*: no creating models, no changing guardrails. Its resources are `foundation-model/*` plus
   this account's `inference-profile/*`, spanning regions because the cross-region `us.*` inference
   profile fans the underlying call across us-east-1/2 + us-west-2. The pinned model id and the
   model-access agreement are what actually gate *which* model answers.
2. **`awsPermissions.policyStatements` — deny-set-validated extras.** Anything beyond the model grant is
   an explicit statement in the claim, validated against the **same escalation deny-set as a tenant
   environment** ([ADR-062](../../adrs/062-self-service-tenant-provisioning.md) §4): the services `iam`,
   `sts`, `organizations`, `account` and any bare `*` wildcard are rejected. And if the platform sets
   `permissionsBoundaryArn`, the minted role is
   **[permissions-boundary](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html)-capped**
   — a hard ceiling the claim cannot raise even if validation were somehow bypassed.

The one live agent uses this exactly as designed: its `awsPermissions` grants `s3:PutObject`/`GetObject`
on the eval-corpus bucket plus KMS data-key actions, nothing more (`gitops/agents/triage-copilot.yaml`).
No `iam`, no `sts`, no `DeleteObject`. That's the shape of a least-privilege agent — a model grant and a
tiny, named, deny-set-clean extension.

## Bound 3 — propose-only, by absence of capability

The sentence that matters most is a design property, not a promise: **the agent's single write action is
posting a message** to the incident surface. There is no write, exec, or remediation verb anywhere in its
grant — not in the ClusterRole, not in the IAM policy, and (per [ADR-080](../../adrs/080-triage-copilot.md)
D4) no remediation tool is wired into the codebase at all. "Propose, don't act" isn't a prompt instruction
it might ignore; it's an IAM-and-code fact. The worst case of a fully hijacked agent is an ignored Slack
message.

This is what "governed principal, not a pod" comes down to. You don't reason with it, trust its plan, or
audit its intentions — you observe that it *cannot* turn a key it doesn't hold.

## Bound 4 — network: default-deny, both directions, and the Cilium trap

RBAC and IAM say *what* it may touch; the network says *where* packets may go. Both directions are
default-deny, and the two directions use **two different mechanisms on purpose** — the sharpest gotcha in
this doc.

**Ingress** is a plain [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/).
A `default-deny-ingress` (`podSelector: {}`, `policyTypes: [Ingress]`) closes everything, then
`allow-trigger-ingress` admits exactly one thing: traffic from the `observability` and `kube-system`
namespaces on port **8080** — the Alertmanager webhook that triggers a triage run. Nothing else can reach
the agent.

**Egress** is a **[CiliumNetworkPolicy](https://docs.cilium.io/en/stable/security/policy/)**, not a
NetworkPolicy with `ipBlock`s — and the comment in the Composition explains why a naive port of the
ingress approach silently breaks:

- The agent's in-cluster destinations (Loki/Mimir gateways, the OTel collector) are matched by **Cilium
  identity**, not CIDR.
- The Pod Identity credential endpoint is **host-local at `169.254.170.23`** — that's `host` traffic, not
  an address a pod `ipBlock` can name.

So a hand-written `ipBlock` egress policy would compile, look correct, and **silently blackhole the
Bedrock credential fetch** — creds fail with no obvious "denied." The CNP instead allows exactly: DNS to
kube-dns (which also powers Cilium's L7 `toFQDNs` IP-learning), the `kube-apiserver` entity (the k8s
read), the `host` entity on port 80 (the Pod Identity agent), the in-cluster `observability` /
`platform-directory` (:5432) / `keycloak` namespaces, and **`toFQDNs`** to
`bedrock-runtime.*.amazonaws.com`, `*.slack.com`, and `api.github.com` on 443 — and nothing else. The
agent literally cannot phone home: no arbitrary internet egress, so no exfiltration path even if hijacked.

## Bound 5 — the data boundary: what may enter the model's context

Bounds 1–4 govern reach; this one governs *content* — because the moment raw telemetry enters a model's
prompt, you've made a data-handling decision ([ADR-076](../../adrs/076-agent-observability.md) D3,
[ADR-080](../../adrs/080-triage-copilot.md) D5). The rules, verbatim on the read side:

- **Metadata is always allowed** — token counts, cost, latency, tool names, verdicts, metric series,
  trace/span metadata, structured-log *fields*, deploy facts, k8s status. Enough for most triage, with no
  free-form content.
- **Raw prompt/response content only behind a per-compliance-tier redaction gate, and in-cluster only —
  never shipped to a SaaS observability backend.** The nuance ADR-076 is careful about: prompts already
  transit Bedrock, so the rule is "no SaaS-obs *side-channel*," not "content never leaves."
- **Regulated tiers ([hipaa/pci](../../adrs/013-compliance-tier-model.md)) are metadata-only, permanently**
  — content capture off, because reliable secret/PII redaction of free-form text is itself an unsolved,
  best-effort problem (same class as prompt-injection detection), and the platform refuses to rely on it
  as a guarantee.
- **Secrets in context is a hard never** — an invariant, not a knob (and Bound 1 already removes the
  capability to read them).
- **The agent's own outputs and reasoning are telemetry under the same boundary** — observability cannot
  become a side channel back out.

This boundary forces the model host. Because raw telemetry (and, for the copilot, source diffs) enters
context, the endpoint must be **in-account** — the public Anthropic API is ruled out for the content path,
since even with federation, content still leaves the cloud. On AWS that means **Bedrock**, reached by
SigV4 straight off the agent's Pod Identity, with no API key to vault. The model is reached through a
thin, platform-owned `Model` port (the first adapter is Bedrock's `Converse` via `aws-sdk-go-v2`, not a
vendor SDK), so swapping models is a config change — though that portability is the design's *promise*;
today one adapter ships.

## Bound 6 — the kill-switch (and the dead-man's-switch design)

Set `lifecycle.phase: suspended` in the claim and commit. In the Composition, `$active` becomes false and
the **`{{- if $active }}` gate omits the `PodIdentityAssociation`** — the agent loses its Bedrock
credentials, so it can't reason. The namespace, SA, and IAM role stay (the slot survives; flip back to
restore), but the fuel is gone.

Why gate there instead of scaling the Deployment to zero? Because **ArgoCD owns the Deployment and would
self-heal a `kubectl scale 0` right back.** The kill is deliberately aimed at the Composition/IAM layer,
which ArgoCD does *not* own — the delivery controller can't revert an identity binding that Crossplane
reconciles from the claim. It's a dead-man's switch: it doesn't ask the agent to stop, it removes the
fuel, at a layer the auto-healer can't undo. The fixture `triage-copilot-suspended.yaml` exists precisely
to render-test that suspend drops the association while keeping the slot.

The honest caveat, where the code is leaner than the ADR: ADR-082 D7 says suspend *also* drops the
Alertmanager route (no triggers). The code doesn't do that. The `trigger` field is XRD-documented as
"Informational — the Alertmanager route is wired separately (Phase 5)," and nothing in the Composition
gates it. So the **code-verified kill is the Bedrock cut** — which is sufficient: no creds, no reasoning;
a firing alert just reaches a defanged agent. Rely on the credential removal, not on triggers stopping.

## The admission plane — keeping the bounds un-bypassable

Six bounds are only as good as the gate that stops a claim from redefining them. Three layers,
defense-in-depth (ADR-082 D6):

1. **XRD enums — the primary guard.** The `XAgent` schema (`xagent-xrd.yaml`) constrains by *type*:
   `placement.cluster` enum `["platform"]` (hub-only), `model.provider` enum `["bedrock","none"]`, and —
   tellingly — `autonomy.mode` enum **`["propose-only"]`**, a single value. The API cannot express an
   autonomous agent; the safety floor is schema-locked. The free-form risk is `awsPermissions`, which is
   why it gets two more layers.
2. **The CI gate `validate-agents.sh`** (`.github/scripts/gitops-gate/`) — shift-left, before merge:
   hub-only placement, a pinned model id (no floating model), the owning **Product** exists with a
   matching team, and the `awsPermissions` deny-set (`iam`/`sts`/`organizations`/`account` + bare `*`).
3. **Hub Kyverno** — two [ClusterPolicies](https://kyverno.io/docs/introduction/) in the
   `agent-policies` chart: `restrict-agent-envelope` re-checks the deny-set and hub-only placement at
   admission, and `restrict-agent-control-plane` allows only platform principals / GitOps to author an
   `XAgent` at all (with `crossplane-system` allow-listed so the Composition's own writes are unaffected).
   Both are installed **after** `agent-api`, so the policy exists before any claim can be admitted.

Above all three, `gitops/agents/` is admin-gated: a platform admin, not the author, must approve the PR,
because authoring an agent grants cluster-read + Bedrock (author ≠ approver for a privileged change,
ADR-074). And because the agent's image now lands on the hub, the hub inherits the `verify-images` /
`verify-attestations` cosign policies for the agent's Product — the signed-image guarantee follows the
workload.

## The one idea that ties it together — the lethal trifecta

Step back and the six bounds are really one defense. The "lethal trifecta" (Simon Willison's framing,
cited in ADR-080) is the combination that makes an LLM agent dangerous: **private data + untrusted content +
an exfiltration path.** Triage genuinely has the first two — telemetry is private, and logs and diffs
are attacker-influenceable content. The whole safety argument is that the third leg does not exist:

- read-only + propose-only (Bounds 1–3): no remediation tool in the grant *or* the codebase;
- output only to Slack (Bound 4's egress lock): no arbitrary internet path to exfiltrate to;
- the data boundary (Bound 5): secrets never enter context to *be* exfiltrated.

Break the third leg and the first two can't hurt you. That's why every bound removes capability rather
than detecting misbehavior — and why "authority lives in trusted code and IAM, never in the prompt" is the
recurring phrase. For a read-only agent, the injection-canary telemetry (action-velocity, escalation-rate)
sits at ~0 by construction, so any nonzero reading is a loud signal.

## Gotchas that teach

- **A read grant is not a network path.** The most common "why is my agent broken" is Bound 4: RBAC and
  IAM can be perfect while the Cilium egress or the ingress admit is missing. Reachability is its own bound.
- **Don't hand-write an `ipBlock` egress for a hub agent.** In-cluster destinations are identity-matched
  and the Pod Identity endpoint is host-local `169.254.170.23` — a CIDR `ipBlock` silently blackholes the
  Bedrock credential fetch. Egress must be a CiliumNetworkPolicy. This one looks correct and fails silently.
- **The kill-switch bites the Composition, not the Deployment.** `kubectl scale 0` is reverted by ArgoCD
  self-heal; only `lifecycle.phase: suspended` (which drops the Pod Identity association) actually stops
  the agent. Know which layer owns which resource.
- **Suspend drops creds, not triggers — today.** ADR-082 D7's "also drops the Alertmanager route" is a
  design statement the Composition doesn't yet implement (the route is Phase-5, wired separately). Rely on
  the credential cut. This is the kind of ADR-says-vs-code-does gap the verification gate exists for.
- **`autonomy.mode` is a one-value enum on purpose.** If you can't set it to `autonomous`, that's not a
  missing feature to file — it's the safety floor, schema-locked until eval-as-a-service exists
  ([autonomy deep dive](deep-dive-autonomy-and-evaluation.md)).

### The three-identities rule — designed, mostly not built

One honest boundary to leave you with, because it's easy to over-claim. An agent's authority is richer
than a plain workload's: the [identity model](../identity/orientation.md) keeps **three** identities
separate — (1) its own workload identity, (2) its tool/model grant, and (3) any on-behalf-of-user
delegation — under the governing rule that **effective authority = the intersection of the agent's grant
and the calling human's scope**, enforced by trusted boundary code, with delegation only ever attenuating.
What's live today is the base of that: the agent's workload identity (Pod Identity) and its tool/model
grant, exactly as this doc describes. The delegation and intersection machinery is largely *designed, not
built* — one agent, autonomously *triggered* but strictly propose-only, with no on-behalf-of-user flow in
production. The model is ready for it; the code isn't there yet.

## Go deeper

- **ADRs (source of truth):** [ADR-074](../../adrs/074-agentic-workloads-platform.md) (the agentic platform,
  *Proposed*), [ADR-082](../../adrs/082-platform-agent-runtime-xagent.md) D5–D8 (identity, admission gate,
  kill-switch, lane posture — *built + live*), [ADR-080](../../adrs/080-triage-copilot.md) D4/D5 (zero-infra
  authority, data boundary + model hosting, the lethal-trifecta analysis),
  [ADR-076](../../adrs/076-agent-observability.md) D3 (the data boundary),
  [ADR-041](../../adrs/041-pod-identity-for-tenant-workloads.md) (keyless Pod Identity).
- **The code:** the [agent Composition](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-api/files/composition.yaml)
  (identity, IAM, the network policies, the kill-switch gate), the
  [obs-read ClusterRole](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-api/templates/platform-trust-cluster-roles.yaml)
  (Secrets-excluded), the [XRD](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-api/templates/xagent-xrd.yaml)
  (the enum guards), the [envelope + control-plane policies](https://github.com/asanexample/platform/blob/main/infra/modules/crossplane/charts/agent-policies/templates/agent-envelope.yaml),
  and the live claim [`gitops/agents/triage-copilot.yaml`](https://github.com/asanexample/platform/blob/main/gitops/agents/triage-copilot.yaml).
- **House skill:** `authoring-platform-agents` — what the Gate and Kyverno will reject, by example.
- **External:** [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
  (AWS docs; ~10 min; the keyless-credential model), [CiliumNetworkPolicy](https://docs.cilium.io/en/stable/security/policy/)
  (Cilium docs, we run v1.19.x; ~15 min; why identity-based egress ≠ `ipBlock`), and Simon Willison's
  ["lethal trifecta"](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) (the framing ADR-080 cites;
  ~5 min).
- **Sideways:** [Bounding vs. the runtime](deep-dive-the-xagent-runtime.md) · [Autonomy & evaluation](deep-dive-autonomy-and-evaluation.md)
  · [Identity & access](../identity/orientation.md) (the three-identities thread) ·
  [Agent observability](../observability/deep-dive-agent-observability.md) (the data boundary, on the telemetry side).
