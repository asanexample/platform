# `agent-policies` chart — the `XAgent` admission gate

Helm chart of **Kyverno ClusterPolicies** that make the platform-agent safety invariants un-bypassable at
admission on the **hub** ([ADR-082](../../../../../docs/adrs/082-platform-agent-runtime-xagent.md) D6). It is
the admission backstop behind the shift-left CI gate (`.github/scripts/gitops-gate/validate-agents.sh`) and
mirrors the tenant `environment-policies` chart. Installed by the `crossplane` module **after** `agent-api`
(which creates the `XAgent` CRD), gated on `enable_agent_api`. Greenfield → **Enforce** from day one.

This is a **chart directory**, not a Terraform module — no `terraform-docs` markers; just this README.

## What it provisions

| File | Policy | What it enforces |
|------|--------|-------------------|
| `templates/agent-envelope.yaml` | `restrict-agent-envelope` (`background: true`) | The **envelope** plane. Rule `policystatements-no-escalation`: an `XAgent`'s `spec.awsPermissions.policyStatements` may not request the deny-set IAM services (`iam`/`sts`/`organizations`/`account`) or a bare `*` — a per-action `foreach` deny (the minted Pod-Identity role is also boundary-capped at runtime, ADR-062 §4 / ADR-082 D5). Rule `placement-hub-only`: defense-in-depth that `spec.placement.cluster` is `platform` (the XRD enum is primary). |
| `templates/agent-control-plane.yaml` | `restrict-agent-control-plane` (`background: false`) | The **control** plane. `XAgent` claims may be authored **only by platform principals** (GitOps / the deployer) — `deny: {}` for everyone else, skipping the allow-listed principals. Defense-in-depth: `XAgent` is cluster-scoped (callers already need cluster RBAC) and `gitops/agents/` is CODEOWNERS-gated; the composite controller + provider-kubernetes author as `crossplane-system` (allow-listed), so the Composition itself is unaffected. `background: false` is required because the rule reads `request.userInfo.username`. |
| `templates/_helpers.tpl` | — | Shared labels (`kap.labels`) + the `kap.skipPlatformPrincipals` match-exclusion (from `excludePrincipals` / `extraExcludePrincipals`). |

## Values

| Key | Default | Purpose |
|-----|---------|---------|
| `validationFailureAction` | `Enforce` | Action for `restrict-agent-control-plane` (who may author an `XAgent`). |
| `envelopeFailureAction` | `Enforce` | Action for `restrict-agent-envelope` (the `awsPermissions` deny-set + placement). |
| `enableAgentEnvelope` | `true` | Render the envelope policy (the module can gate it off for an Audit-first roll). |
| `failurePolicy` | `Fail` | Webhook failure policy (fail-closed under Enforce). |
| `excludePrincipals` | argocd / kube-system / crossplane-system SAs, nodes, kube-controller-manager | Principals skipped by `restrict-agent-control-plane` (the GitOps + composite writers). |
| `extraExcludePrincipals` | `[]` | Env-specific additions (unused on the hub — ArgoCD is in-cluster). |
| `iamSensitiveServices` | `[iam, sts, organizations, account]` | The platform-global IAM deny-set; a bare `*` matches any entry. Identical to the tenant deny-set — agents get no exception. |
| `commonLabels` | `{}` | Extra labels on every ClusterPolicy. |

Overrides come from the `crossplane` module's `agent_policy_values` input (merged over these defaults). The
defaults exist so `helm template` + the `.kyverno-tests` harness work standalone.

## See also

- [ADR-082](../../../../../docs/adrs/082-platform-agent-runtime-xagent.md) D6 — the admission gate · [ADR-062](../../../../../docs/adrs/062-self-service-tenant-provisioning.md) §4 — the IAM deny-set · [ADR-014](../../../../../docs/adrs/014-kyverno-as-policy-engine.md) — Kyverno
- `.github/scripts/gitops-gate/validate-agents.sh` — the shift-left counterpart
- `infra/modules/crossplane/charts/agent-api/` — the control plane this guards (sibling chart) · `authoring-platform-agents` skill
