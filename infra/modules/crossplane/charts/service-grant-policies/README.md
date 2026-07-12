# `service-grant-policies` chart — the `ServiceGrant` admission gate

Helm chart of **Kyverno ClusterPolicies** that make the ServiceGrant safety invariants un-bypassable at
admission (ADR-101). It is the admission backstop behind the shift-left CI gate
(`.github/scripts/gitops-gate/validate-service-grants.sh`) and mirrors the `agent-policies` chart. Installed by
the `crossplane` module **after** `service-grant-api` (which creates the `ServiceGrant` CRD), gated on
`enable_environment_api` (ServiceGrant only makes sense where XEnvironments exist). Greenfield → **Enforce**
from day one — this protects the grant OBJECT itself, not a pre-existing claim, so there is no
"breaks existing traffic" risk to phase in (unlike `environment-policies`' `restrict-environment-dependencies`,
which IS Audit-first).

This is a **chart directory**, not a Terraform module — no `terraform-docs` markers; just this README.

## What it provisions

| File | Policy | What it enforces |
|------|--------|-------------------|
| `templates/service-grant-admission.yaml` | `restrict-service-grant-admission` (`background: false`) | Rule `deny-non-platform-service-grant`: a `ServiceGrant` may only be authored/modified by the GitOps controller identity (mirrors `restrict-agent-control-plane`) — defense-in-depth behind `gitops/grants/`'s per-team ownership (enforced by the gate script, not CODEOWNERS). Rule `deny-regulated-tier-service-grant`: neither `target` nor `subject` may resolve (via a live lookup of every `XEnvironment` on the cluster, filtered by `{team,product,stage}`) to a `hipaa`/`pci` tier — mirrors the cross-team observability grants' regulated-tier exclusion. |
| `templates/_helpers.tpl` | — | Shared labels (`ksp.labels`), the `ksp.skipAllowedPrincipals` match-exclusion (from `excludePrincipals`/`extraExcludePrincipals` — an ALLOW-list in effect), and `ksp.xenvironmentsContext` (the `context.apiCall` list-and-filter used to resolve a named Environment's tier). |

## Why tier is read from `XEnvironment`, not `Team`/`Product`

Neither the projected `Team` nor `Product` CR carries a single "this is regulated" tier — `Team.envelope.
allowedTiers` is only the SET of tiers a Team is allowed to use across all its Environments. The actual tier a
specific `{team, product, stage}` runs at lives on that stage's own `XEnvironment` claim (`spec.tier`). So the
regulated-tier check here lists every `XEnvironment` and filters by `{team, product, stage}` to find the one
naming the `ServiceGrant`'s `target`/`subject`, rather than doing a `Team`/`Product` lookup the way
`environment-policies`' envelope rules do.

## Fail-open/closed posture (read before touching the context calls)

Both `context.apiCall` entries (`ksp.xenvironmentsContext` here; the sibling `ktp.serviceGrantsContext` in
`environment-policies`) deliberately omit `default` — Kyverno only fails a rule's evaluation on a **real**
`apiCall` error when no `default` is configured; a plain LIST call that legitimately matches nothing still
succeeds with `items: []`. Combined with `failurePolicy: Fail`, a genuine fetch failure denies. Note the
**asymmetry** between the two policies: `restrict-environment-dependencies` is "deny unless a matching grant is
found", so an empty/erroring list denies correctly either way (fail-closed twice over). This chart's
regulated-tier rule is "deny IF a match resolves to hipaa/pci" — the opposite polarity — so an empty/erroring
`xenvironments` list here fails **open** for that one rule (no evidence of regulated tier ⇒ admitted). That is
an accepted, deliberate gap: `validate-service-grants.sh` independently re-derives the same tier from the
actual claim file in git and rejects there too, so this is not the only enforcement layer. A stricter variant
that hard-denies whenever tier is unresolvable is a reasonable future tightening if this proves insufficient.

## Values

| Key | Default | Purpose |
|-----|---------|---------|
| `validationFailureAction` | `Enforce` | Action for both rules. |
| `failurePolicy` | `Fail` | Webhook failure policy (fail-closed under Enforce). |
| `excludePrincipals` | argocd / kube-system / crossplane-system SAs, nodes, kube-controller-manager | The allow-list — principals permitted to author a `ServiceGrant`. |
| `extraExcludePrincipals` | `[]` | Env-specific additions (e.g. ArgoCD's cross-account assumed-role identity on a workload cluster). |
| `commonLabels` | `{}` | Extra labels on the ClusterPolicy. |

Overrides come from the `crossplane` module's `service_grant_policy_values` input (merged over these
defaults). The defaults exist so `helm template` + the `.kyverno-tests` harness work standalone.

## See also

- [ADR-101](../../../../../docs/adrs/101-service-grant-cross-team-network-capability.md) — the ServiceGrant
  primitive this guards (once written) ·
  [ADR-068](../../../../../docs/adrs/068-product-scoped-and-cross-team-access-model.md) — the sibling
  `AccessGrant` vocabulary · [ADR-014](../../../../../docs/adrs/014-kyverno-as-policy-engine.md) — Kyverno
- `.github/scripts/gitops-gate/validate-service-grants.sh` — the shift-left counterpart
- `infra/modules/crossplane/charts/service-grant-api/` — the control plane this guards (sibling chart)
