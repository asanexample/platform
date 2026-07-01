# Runbook: Platform-Agent Operations (`XAgent`)

> **Purpose:** operate a **live platform agent** day-2 — deploy, observe, suspend (the kill-switch), and
> reason about its autonomy/guardrail envelope. The reference agent is the **triage copilot**
> ([ADR-080](../adrs/080-triage-copilot.md)); the runtime is the `XAgent` control plane
> ([ADR-082](../adrs/082-platform-agent-runtime-xagent.md)). For *authoring* a new agent (the `XAgent` claim
> shape, the gate, the Product join), use the **`authoring-platform-agents`** skill.
>
> **Last reviewed:** 2026-06-28

---

## What a platform agent is (the operating model)

Platform agents **run on the hub** (the platform cluster) — that is where the data is: observability is
hub-central (every spoke ships there) and the control plane (ArgoCD sync history, the registries) is
hub-resident. An agent is **read-only + propose-only** by construction (ADR-074 / ADR-082 D5): it gathers
evidence and proposes — it never writes, execs, or remediates. Its only egress is to **Bedrock** (the model),
the **incident channel** (Slack), the **k8s API + the observability stores** (read), and `api.github.com`
(change-correlation read). The runtime adds **zero write capability** — that's the lethal-trifecta defense.

A live agent has two halves (both on the hub):

- **The runtime slot** — namespace `platform-agent-<name>`, the named ServiceAccount, the EKS **Pod Identity**
  role (the Bedrock grant + any `awsPermissions`), the obs-read RBAC binding, and the ingress/egress
  NetworkPolicies. Provisioned by the **Crossplane Agent Composition** from the `XAgent` claim.
- **The workload** — the agent's Deployment (+ Service/ConfigMap/ExternalSecret), delivered by **ArgoCD**
  with the promoted, signed image digest.

## Deploy / update an agent

Deployment is **GitOps** — there are no imperative deploy steps:

- **A new agent, or a claim change** (e.g. toggling `obsRead`, adding an `awsPermissions` statement): edit
  `gitops/agents/<name>.yaml`, open a PR (CODEOWNERS-gated + `validate-agents.sh`), merge. The `agents`
  registry-sync Application projects it to the hub Crossplane, and the Composition reconciles the slot.
- **A new agent image / behaviour change**: the app repo builds → signs → promotes a digest into
  `gitops/releases/<team>/<product>/`; the per-agent ApplicationSet (`agent-<name>`) injects the digest and
  ArgoCD syncs it. A **manifest-only** change to the app repo delivers on the next sync at
  `targetRevision: HEAD` — **no rebuild** (only the image *digest* is Release-pinned, ADR-071).

Cluster access for any of the read-back commands below is over **Tailscale** (the EKS API is private-only,
ADR-010) — see the `cluster-access` skill. Note clusters are **parked** in some windows; if there's no node
capacity the agent won't be scheduled.

### Verify the slot + workload (hub context)

```bash
NS=platform-agent-<name>

# The claim and its provisioned status (status.namespace / status.roleArn are set by the Composition)
kubectl --context platform get xagent <name> -o yaml

# The Composition-made slot
kubectl --context platform get ns "$NS"
kubectl --context platform -n "$NS" get sa,deploy,svc
kubectl --context platform -n "$NS" get networkpolicy,ciliumnetworkpolicy

# The obs-read binding (only when spec.obsRead: true)
kubectl --context platform get clusterrolebinding platform-agent-<name>-obsread

# Delivery health
kubectl --context platform -n argocd get applications.argoproj.io -l platform.refplat.org/agent=<name>
```

## Observe an agent — where its telemetry lands

Agent telemetry follows the **OTel + GenAI-semconv** model of [ADR-076](../adrs/076-agent-observability.md):
emit once, land in the hub LGTM+P stack (tenant `platform`). The agent is **tier-0** — instrumented like any
platform workload, plus GenAI spans.

- **Dashboard:** **"Triage Agent (ADR-076)"** — shipped as dashboards-as-code in the `observability` module
  (`infra/modules/observability/dashboards/agent-triage.json`, projected into Grafana as a ConfigMap). Panels
  cover **Est. cost / day**, **Invocation rate**, **Token rate by type**, **Operation latency (p50/p95)**,
  **Disposition mix**, **Tool calls**, and the Slice-3 **Eval / calibration** (Human verdicts, Accept-rate by
  disposition). Metrics are scraped from the agent's `/metrics` ServiceMonitor → Mimir.
- **Traces:** GenAI spans (model invoke, tool calls) → the OTel Collector → Tempo. Note OTel traces can be
  network-blocked in places, so the agent also logs per-tool **gather** output to **stdout** (→ Loki) — stdout
  is the real debugging surface when a trace is missing (ADR-082 learning).
- **Logs:** the agent's stdout → Loki (tenant `platform`).
- **Live signals:** use the **grafana MCP** / the `firing-alerts` skill for what's firing; the agent itself is
  *triggered by* Alertmanager (a curated route, see below) and posts its hypotheses to the incident Slack channel.

Multi-cluster: a spoke/preprod alert reaches the agent via the **Mimir ruler** (so a spoke alert can fire at
all), the obs query tenant follows the alert's `cluster` label (`X-Scope-OrgID`), and "what changed" is read
**hub-local from ArgoCD** sync history — the agent never touches the spoke's API (ADR-082 D2, refined).

## The eval capture substrate (forward-capture)

The triage agent's evaluation corpus is **built forward** ([ADR-080](../adrs/080-triage-copilot.md) D6): telemetry
retention is short, so a real incident not captured *when it fires* is lost. At triage time the agent writes a
**write-once fixture** — `{alert-group, telemetry snapshot, structured label, rubric}` — into the durable corpus,
and its label **back-fills later** from the accept/reject signal (and the eventual RCA). Accrued forward, this is
the `production-shadow` source that feeds the `shadow → proven → promoted` graduation signal
([ADR-086](../adrs/086-autonomous-agent-access.md)).

- **Store:** the `agent-eval-store` unit provisions a durable, keep-forever S3 bucket **`platform-agent-eval-corpus`**
  (platform account) — dedicated CMK (SSE-KMS), TLS-only, versioned, write-once (the agent has `PutObject`/`GetObject`
  but **no `DeleteObject`**), and `teardown_skip` so it survives a rebuild (like the state backend). Provisioned
  independently of any agent version.
- **Write access:** identity-based on the agent's Pod-Identity role, declared in `gitops/agents/triage-copilot.yaml`
  (`awsPermissions.policyStatements`: S3 object write + KMS use). No cross-account read role exists yet (the module's
  `reader_role_arns` seam is empty until a CI replay/grader lands, ADR-080 D6 — an app-repo follow-up).
- **Config contract (app repo):** the agent reads the target bucket from config; the name is the deterministic
  constant `platform-agent-eval-corpus`. **Metadata-first** — capture structured values + bounded context, **not**
  raw unredacted logs/traces, until ADR-076's content-capture-with-redaction lands.

### Capture-health

A silently-failing capture makes the "ready-for-scale" premise quietly false, so watch it. Today only the
**trigger layer** is observable: **`AgentTriageWebhookDeliveryFailing`** (curated alert) fires when Alertmanager
webhook delivery fails — the agent isn't receiving criticals, so it can neither triage nor capture. The fuller
**"fixtures captured == 0 while criticals fired"** alert lands once the agent emits an
`agent_eval_fixtures_captured_total` counter on its `/metrics` endpoint (→ Mimir, the ADR-076 path).

### Synthetic-alert isolation (convention for the injection slice)

A later slice adds an autonomous **fault-injection** runner (bounded catalog, walled-off namespace) to bootstrap
the corpus with self-labeled known failures. Its injected alerts **MUST** carry the label **`synthetic="true"`**;
the injection slice then adds an Alertmanager route fanning `synthetic="true"` to the `triage` receiver **only —
never PagerDuty/SNS** (modeled on the `Watchdog → null` pattern), so a fake incident can't page real on-call or
@mention a real culprit. The convention is documented now; the route ships with its producer.

## Suspend an agent — the kill-switch

To stop an agent **now**, set its lifecycle phase to `suspended` and commit:

```yaml
# gitops/agents/<name>.yaml
spec:
  lifecycle:
    phase: suspended   # was: active
```

On the next sync the Composition **removes the Pod Identity association** — a hard stop: **no Bedrock, the
agent cannot reason.** This is enforced where it bites, not at the Deployment: ArgoCD owns the Deployment and
would revert a naïve `kubectl scale 0` (selfHeal), so the kill-switch works at the Composition/identity layer.
The pod keeps running but is **defanged**. (The Alertmanager route also drops a suspended agent, so no new
triggers arrive.)

```bash
# Verify the hard stop — the PodIdentityAssociation should be gone for the agent's SA
kubectl --context platform get podidentityassociations.eks.aws.upbound.io \
  -o yaml | grep -A3 "serviceAccount: <name>"   # expect: none for a suspended agent
```

**Reverse:** flip `phase` back to `active`, commit — the association is re-minted and the agent resumes.

> The kill-switch is the **reversible** stop. A full removal (delete `gitops/agents/<name>.yaml`) tears down
> the slot (namespace + identity + RBAC); the app's ECR images are Product-scoped and retained, as for
> environments. Prefer `suspended` for an incident; delete only to decommission the agent for good.

## The autonomy / guardrail envelope

What bounds a live agent, and where each guard lives:

| Guard | Where it's enforced | What it bounds |
|-------|---------------------|----------------|
| **propose-only** | XRD enum (`autonomy.mode`) + the agent | read + propose, **never act** — the ADR-074 safety invariant |
| **No Secrets** | `platform-trust-observability-reader` ClusterRole | secret *values* never enter the agent / model context |
| **IAM deny-set** | `validate-agents.sh` + Kyverno `restrict-agent-envelope` + the runtime permissions boundary | `awsPermissions` can't request `iam`/`sts`/`organizations`/`account` or bare `*` (ADR-062 §4) |
| **Bedrock data-plane only** | the Composition's minted role | invoke/converse only — never Bedrock *management* |
| **Hub-only placement** | XRD enum + the gate + Kyverno | the agent runs only on the platform cluster (ADR-082 D2) |
| **Egress lockdown** | the Composition's Cilium egress policy | egress only to DNS + kube-apiserver + host(Pod-Identity) + the obs ns + `toFQDNs` Bedrock/Slack/GitHub |
| **Ingress lockdown** | the Composition's k8s NetworkPolicies | default-deny ingress; only the obs ns (Alertmanager webhook) + kube-system on 8080 |
| **Storm / cost controls** | `autonomy.maxConcurrent` / `autonomy.tokenBudget` (enforced by the agent) | runner concurrency cap + a rolling token/cost circuit breaker |
| **Curated trigger** | the Alertmanager route (wired separately) | a `triage: enabled` / severity match — never a catch-all |
| **Hub-write blast radius** | the per-agent AppProject (`clusterResourceWhitelist: []`) | ArgoCD delivers only namespaced workload kinds; all cluster-scoped identity/RBAC comes from the gated Composition |
| **Author ≠ approver** | CODEOWNERS on `gitops/agents/` | granting an agent cluster-read + Bedrock is an admin/platform-reviewed PR |

If a triggered agent is **abstaining on every alert**, that's the designed-safe failure (it's read-only) —
common live causes were a missing change-correlation tool, an unmounted SA token, or the obs namespace
default-deny ingress; see the ADR-082 "Implementation status & learnings" section.

## Residual / out of scope

- **Cross-cluster k8s read** (`access.clusters`) is **Phase 2** — the schema exists; the target-cluster read
  roles don't. Today the agent triages from hub-central obs + ArgoCD change history alone (ADR-082 D2).
- **Running an agent *on* a workload cluster** (per-cluster `XAgent` federation) is deferred — agents are
  hub-only today.
- The forward-capture **corpus** substrate is built (see "The eval capture substrate" above); the eval
  **grader / CI regression gate** (app repo), the autonomous fault-injection **runner**, and ADR-076
  content-capture remain tracked follow-ups (ADR-080/082).

## References

- [ADR-082](../adrs/082-platform-agent-runtime-xagent.md) — the `XAgent` runtime · [ADR-080](../adrs/080-triage-copilot.md) — the reference agent · [ADR-074](../adrs/074-agentic-workloads-platform.md) — safety invariants · [ADR-076](../adrs/076-agent-observability.md) — the agent-trace model
- `authoring-platform-agents` skill — authoring a new `XAgent` claim
- `gitops/agents/` — the claim registry · `infra/modules/crossplane/charts/agent-api/` + `.../agent-policies/` — the control plane · `infra/modules/argocd-apps/agents.tf` — delivery
- `cluster-access` skill — reaching the private hub EKS API over Tailscale
