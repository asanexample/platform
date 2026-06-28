# How-to — extend & tune zero-downtime (platform engineers)

Recipes for changing the machinery. For the mechanism, see the
[platform internals](overview-platform.md); for incidents, the
[operations runbook](../../runbooks/rollout-and-gate-operations.md).

## Enable / disable an availability default

Each ADR-085 rule has a module toggle on the `policy` unit — flip the input and apply:

| Toggle (`policy` module var) | Controls |
|---|---|
| `enable_mutate_defaults` | the `add-pod-defaults` mutate (preStop + terminationGracePeriod + securityContext) |
| `enable_pdb_generate` | the generated `maxUnavailable: 1` PDB |
| `enable_topology_spread` | the injected `topologySpreadConstraints` |
| `enable_replica_floor` | the `require-prod-replica-floor` validate |

These are **enable/disable**, not value knobs.

## Change a default *value* (preStop, grace period, PDB)

The values (`preStop.sleep.seconds: 10`, `terminationGracePeriodSeconds: 30`, PDB `maxUnavailable: 1`,
the topology keys) are **hardcoded in the policy chart templates**, not Helm values —
`infra/modules/policy/policies-chart/templates/{mutate-pod-defaults,generate-pdb,mutate-topology-spread}.yaml`.
Changing one is a **module edit** (then `kyverno test` under `.kyverno-tests/`, apply both clusters).
Keep `terminationGracePeriodSeconds` > preStop sleep + the app's drain budget. See the
**kyverno-policy-authoring** house skill.

## Flip a validate policy Audit → Enforce (e.g. the replica floor)

> **Note:** the replica floor (`require-prod-replica-floor`) is **already promoted to Enforce on both live
> clusters** (#934) — it's used here only as a worked example of the generic promotion procedure. Apply these
> steps to whichever validate policy is still Audit.

The validate policies roll **audit-first** so you review before they reject. To promote one:

1. **Review the audit** — there must be no live violations, or you'll break a deploy:

   ```bash
   kubectl get clusterpolicyreport,policyreport -A -o json \
     | jq '[.items[].results[] | select(.policy=="require-prod-replica-floor" and .result!="pass")]'
   ```

2. Set the action input on **both** policy units (keep the module default `Audit` so fresh clusters
   stay audit-first): `replica_floor_failure_action = "Enforce"`.
3. Apply each cluster (`0 destroy` — it's a `failureAction` flip), then verify a violating dry-run is
   rejected:

   ```bash
   kubectl -n <team>-<product>-prod patch rollout app-<…> --type=merge \
     -p '{"spec":{"replicas":1}}' --dry-run=server   # -> denied by require-prod-replica-floor
   ```

(Kyverno 1.18 uses the **per-rule** `validate.failureAction`, not `spec.validationFailureAction`.)

## Add or change a metric gate

Gates live in the scaffolder's **prod overlay** —
`scaffolder/templates/new-product/skeleton/k8s/overlays/prod/`:

- `progressive.yaml` — the `AnalysisTemplate`(s): the Mimir address, the PromQL `query`, and the
  `successCondition` (e.g. `result[0] >= 0.95` for the canary gate, `result[0] < 2` for the freeze).
- `kustomization.yaml` — wires the template in as a **background** analysis (continuous, on the
  canary) or a **pre-flight** step (`count: 1`, before `setWeight`).

Changing the scaffolder affects **new** Products. To add a gate to an **existing** app, make the same
edit in that app's `k8s/overlays/prod` (this is how the W11 freeze was retrofitted onto alpha-shop).
Use the **argocd-app-delivery** house skill for the ArgoCD `ignoreDifferences` requirements.

## Onboard / customize a per-app SLO

Every prod environment **already** gets a 99.9% availability SLO automatically — the `mimir` unit
derives one per prod `XEnvironment` claim (`gitops/environments/**/prod.yaml`) into the Mimir ruler
(`var.app_slos`, registry-as-source). There's nothing to onboard.

To **customize** the objective per Product/tier (not yet a knob): extend the `app_slos` derivation in
`infra/live/.../mimir/terragrunt.hcl` (e.g. read an objective off the Product registry), re-render
the `app-slo-rules.yaml.tftpl`, and sync the ruler. See the **observability-authoring** house skill.

## Point a metric gate at a new cluster

The gate runs where the rollout's cluster can **read** Mimir. A spoke is write-only by default, so a
new prod cluster needs the **spoke→hub Mimir read route** wired first
(`observability-mimir` `spoke_ingest.query_tenants`) — a small networking change, *not* a new Mimir.
The Argo Rollouts controller itself is per-cluster (an addon); the AnalysisTemplate's `address` points
at the hub read route. When a dedicated prod cluster lands, repoint the gate's `address` there.

## See also

- [Platform internals](overview-platform.md) · [Architecture](../../architecture/zero-downtime-deployments.md)
- [Operations runbook](../../runbooks/rollout-and-gate-operations.md)
- ADRs [085](../../adrs/085-workload-availability-graceful-disruption-defaults.md) /
  [056](../../adrs/056-progressive-delivery-and-safe-rollback.md)
