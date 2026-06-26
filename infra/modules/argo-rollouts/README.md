# argo-rollouts

Installs the [Argo Rollouts](https://argo-rollouts.readthedocs.io/) controller + CRDs — the
progressive-delivery control plane ([ADR-056](../../../docs/adrs/056-progressive-delivery-and-safe-rollback.md)).
Every environment workload becomes a `Rollout` (direct `spec.template`); the tier picks the *strategy*
(dev/preprod auto-promote to dogfood the path; prod metric-gated canary).

Pure in-cluster controller — no AWS identity. Metric-gated analysis (against the hub Mimir) and the Gateway-API
traffic-router plugin (weighted HTTPRoute canary) are wired in a later phase, not here.

## Ordering

The CRDs must exist **before** the `policy` unit: the ADR-085 availability policies
(`generate-workload-pdb`, `mutate-topology-spread`, `require-prod-replica-floor`) match the `Rollout` kind, and
a Kyverno rule naming a kind whose CRD is absent fails to create (Kyverno #7839). DAG slot: **after `gateway`,
before `policy` and `argocd-apps`** — enforced by the `policy` unit declaring a dependency on this unit.

## Inputs of note

`helm_chart_version` (pinned in `_versions.hcl` → `helm_versions.argo_rollouts`), `replica_count` (1 non-prod,
2+ for HA on the platform/hub cluster), `namespace` (default `argo-rollouts`).
</content>
