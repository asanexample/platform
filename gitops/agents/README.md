# Platform agents — `XAgent` claims (ADR-082)

The GitOps source of truth for **platform agents**: each `gitops/agents/<name>.yaml` is an `XAgent` claim
(the runtime side of ADR-074). ArgoCD's `agents` registry-sync projects them onto the **hub** Crossplane, where
the Agent Composition provisions the agent's runtime slot (namespace `platform-agent-<name>`, a Pod-Identity
role with the model's Bedrock grant, and — when `obsRead` — the read-only observability RBAC). The agent's
**workload** is delivered separately by the per-agent ApplicationSet (the promoted, signed image digest).

Authoring an agent here grants cluster-read + Bedrock, so this path is **CODEOWNERS-gated** and validated by the
CI gate (`validate-agents.sh`) + Kyverno (`restrict-agent-envelope`) before admission.

```yaml
# gitops/agents/<name>.yaml
apiVersion: platform.refplat.org/v1beta1
kind: XAgent
metadata:
  name: triage-copilot          # → namespace platform-agent-triage-copilot, SA + role named from it
spec:
  team: platform                # owning Team (join key to the Product registry)
  product: triage-copilot       # owning Product (image/ECR/signing via the supply chain)
  placement: { cluster: platform }   # hub-only today (ADR-082 D2)
  model: { provider: bedrock, id: us.anthropic.claude-sonnet-4-6 }   # pinned; mints the Bedrock grant
  obsRead: true                 # bind platform-trust-observability-reader (cluster-wide read, no Secrets)
  autonomy: { mode: propose-only }
  trigger: { kind: alertmanager-webhook }
  lifecycle: { phase: active }  # `suspended` = the kill-switch (drops the Pod Identity)
```

See `docs/adrs/082-platform-agent-runtime-xagent.md`.
