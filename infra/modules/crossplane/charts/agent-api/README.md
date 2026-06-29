# `agent-api` chart — the `XAgent` platform-agent control plane

Helm chart that installs the **platform-agent control plane** on the **hub** (platform cluster) Crossplane —
the runtime side of [ADR-074](../../../../../docs/adrs/074-agentic-workloads-platform.md), realized in
[ADR-082](../../../../../docs/adrs/082-platform-agent-runtime-xagent.md). It mirrors the tenant `environment-api`
chart but is **agent-shaped and lean** (no quotas/tiers/stages/isolation/developer-access/domains). Installed
**once** by the `crossplane` module (`enable_agent_api`, hub only); after that, adding an agent is a git commit
(an `XAgent` claim in `gitops/agents/`) — no `terragrunt apply` per agent.

This is a **chart directory**, not a Terraform module — no `terraform-docs` markers; just this README.

## What it provisions

| File | Resource | Purpose |
|------|----------|---------|
| `templates/xagent-xrd.yaml` | `CompositeResourceDefinition` `xagents.platform.refplat.org` | The **`XAgent`** API (`apiextensions.crossplane.io/v2`, **cluster-scoped** — the `XAgent` *is* the claim, like `XEnvironment`). Lean, agent-shaped schema: `team`/`product` (required), `placement` (hub-only enum), `model` (Bedrock + pinned id), `obsRead`, `access` (Phase-2 cross-cluster read), `awsPermissions.policyStatements` (deny-set), `autonomy` (propose-only), `trigger`, `lifecycle` (active/suspended kill-switch). |
| `files/composition.yaml` + `templates/composition.yaml` | `Composition` `agent` (Pipeline mode) | Renders an `XAgent` into its runtime **slot**: namespace `platform-agent-<name>`, a named ServiceAccount, an EKS **Pod Identity** role (the model's Bedrock data-plane grant + deny-set-validated `awsPermissions`, permissions-boundary-capped), the obs-read `ClusterRoleBinding` (when `obsRead`), and the ingress (k8s) + egress (Cilium) NetworkPolicies. The agent's **workload** is delivered separately by ArgoCD — the Composition does **not** render it. Shipped raw (`.Files.Get`) so Helm leaves the Crossplane go-template delimiters intact; render-tested with `crossplane render`. The pipeline is `function-environment-configs` → `function-go-templating` → `function-auto-ready`. |
| `templates/agentconfig.yaml` | `EnvironmentConfig` `platform-agent-config` | Cluster constants the Composition reads via `.context` (hub `clusterName`, `region`, `workloadAccountId`, the agent permissions-boundary ARN) — Helm-templated from the module's `agent` input so the Composition stays cluster-agnostic. |
| `templates/platform-trust-cluster-roles.yaml` | `ClusterRole` `platform-trust-observability-reader` | The fixed, platform-provided read-only profile an `XAgent`'s `obsRead: true` binds to its SA: read of pods/events/services/deployments + ArgoCD `Applications` + the `Product` registry. **No Secrets.** Installed here (gated on `createObsReaderClusterRole`) because the `environment-api` chart is **not** deployed on the hub, so the binding needs a local copy of the role. |

## The kill-switch (`lifecycle.phase`)

`spec.lifecycle.phase: suspended` makes the Composition **drop the `PodIdentityAssociation`** — a hard stop
(no Bedrock, the agent can't reason), selfHeal-proof because the ArgoCD-owned Deployment keeps running but is
defanged. Back to `active` re-mints it. See `docs/runbooks/agent-operations.md`.

## Values

| Key | Default | Purpose |
|-----|---------|---------|
| `agent` | `{}` | The `AgentConfig` constants (`clusterName`, `region`, `workloadAccountId`, `permissionsBoundaryArn`); the template guards on `.Values.agent`, so empty = no `EnvironmentConfig`. |
| `createObsReaderClusterRole` | `true` | Install `platform-trust-observability-reader` on this cluster (the `obsRead` profile). |

Set by the `crossplane` module on the hub unit (`enable_agent_api`). The companion **`agent-policies`** chart
installs the admission gate (`restrict-agent-envelope` / `restrict-agent-control-plane`) and is applied
**after** this chart (which creates the `XAgent` CRD).

## See also

- [ADR-082](../../../../../docs/adrs/082-platform-agent-runtime-xagent.md) — the design · `authoring-platform-agents` skill · `docs/runbooks/agent-operations.md`
- `gitops/agents/` — the `XAgent` claim registry · `infra/modules/argocd-apps/agents.tf` — the registry-sync + per-agent workload delivery
- `infra/modules/crossplane/charts/agent-policies/` — the admission policies (sibling chart)
