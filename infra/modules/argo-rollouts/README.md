# argo-rollouts

Installs the [Argo Rollouts](https://argo-rollouts.readthedocs.io/) controller + CRDs — the
progressive-delivery control plane ([ADR-056](../../../docs/adrs/056-progressive-delivery-and-safe-rollback.md)).
Every environment workload becomes a `Rollout` (direct `spec.template`); the tier picks the *strategy*
(dev/preprod auto-promote to dogfood the path; prod metric-gated canary).

Pure in-cluster controller — no AWS identity. Installs the **Gateway-API traffic-router plugin**
(`enable_gateway_api_plugin`, default on) so Rollouts can do weighted HTTPRoute canary on the Cilium Gateway —
the controller downloads the arch-matched binary at startup (`gateway_api_plugin_version` / `_arch`; Graviton
arm64), and the bundled ClusterRole already grants the `httproutes` RBAC. It's inert until a Rollout opts in
via `strategy.canary.trafficRouting.plugins."argoproj-labs/gatewayAPI"`. Metric-gated analysis (the per-app
`AnalysisTemplate` querying Mimir) lands in a later phase.

## Ordering

The CRDs must exist **before** the `policy` unit: the ADR-085 availability policies
(`generate-workload-pdb`, `mutate-topology-spread`, `require-prod-replica-floor`) match the `Rollout` kind, and
a Kyverno rule naming a kind whose CRD is absent fails to create (Kyverno #7839). DAG slot: **after `gateway`,
before `policy` and `argocd-apps`** — enforced by the `policy` unit declaring a dependency on this unit.

## Inputs of note

`helm_chart_version` (pinned in `_versions.hcl` → `helm_versions.argo_rollouts`), `replica_count` (1 non-prod,
2+ for HA on the platform/hub cluster), `namespace` (default `argo-rollouts`).
</content>
