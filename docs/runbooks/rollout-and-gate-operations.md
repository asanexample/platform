# Runbook — rollout & metric-gate operations

Platform-side operational procedures for progressive delivery (ADR-056). Developer-facing symptoms
are in the [developer troubleshooting guide](../guides/zero-downtime/troubleshooting-developers.md);
this covers the cluster-side diagnosis + fixes.

First command, always:

```bash
kubectl argo rollouts get rollout <app> -n <ns> --watch          # step, weights, analysis verdicts
kubectl -n <ns> get analysisrun -o wide                           # the gate runs
kubectl -n argo-rollouts logs deploy/argo-rollouts --tail=200     # controller (per cluster)
```

## A rollout is Degraded / aborted

The metric gate (or the freeze) failed. Identify which:

```bash
kubectl -n <ns> get analysisrun -o json | jq '.items[] | {name:.metadata.name, phase:.status.phase, msg:.status.message}'
kubectl -n <ns> describe analysisrun <name>     # the measurement values + error
```

- `…-canary-gate` Failed → the new version's success rate dropped → it's a **bad version** (fix
  forward, or re-promote the previous digest).
- `…-budget-freeze` Failed at step 0 → the service was **already over budget** (see "freeze
  blocking" below).

## The metric gate returns "no data" / Inconclusive / Error

The gates are fail-open on empty results, so this manifests as gates that **never catch anything**.
Causes, in order of likelihood:

1. **Not enough canary traffic** to compute a rate (low-traffic service) — expected; consider
   blue-green for that app.
2. **The spoke→hub Mimir read path is down.** Confirm whether Mimir is even answering:

   ```bash
   GW=$(kubectl -n observability get pod -l app.kubernetes.io/name=mimir --no-headers | grep '^mimir-gateway-' | awk '{print $1}' | head -1)
   kubectl -n observability exec "$GW" -- sh -c "wget -q -O- --header='X-Scope-OrgID: <tenant>' 'http://localhost:8080/prometheus/api/v1/query?query=slo:current_burn_rate:ratio'"
   ```

   ⚠️ **Known post-unpark failure:** the gossip-ring DNS gap on unpark can degrade the Mimir
   **query-frontend**, and the API gateway caches a **stale upstream** to it — so the gateway returns
   empty while the **querier serves fine directly**. Fix: restart the query path, then the API
   gateway (scope the gateway delete with `name=mimir` so it hits only the API gateway):

   ```bash
   # Two -l flags on the SAME label key AND-combine and match nothing — use a set-based selector:
   kubectl -n observability delete pod -l 'app.kubernetes.io/component in (query-frontend,query-scheduler)'
   kubectl -n observability delete pod -l app.kubernetes.io/component=querier
   kubectl -n observability delete pod -l app.kubernetes.io/name=mimir,app.kubernetes.io/component=gateway   # the API gateway
   ```

3. **The SLO rules aren't in the ruler.** The `slo:*` series are produced by the Mimir ruler from
   per-app rules synced by a CronJob:

   ```bash
   kubectl -n observability create job slo-sync-now --from=cronjob/mimir-ruler-rules-sync-<tenant>
   kubectl -n observability logs job/slo-sync-now | grep -i 'Sync Summary'   # Groups Created/Updated
   ```

## The error-budget freeze is blocking deploys

A deploy aborts at step 0 because `slo:current_burn_rate:ratio ≥ 2×`. Decide if it's real:

- **Real incident** (the service *is* burning budget) — the freeze is correct. Resolve the
  degradation; the next deploy proceeds once the burn rate recovers. Check **Grafana → SLO
  dashboard**.
- **Stale / wrong SLO** (the burn metric is wrong, not the service) — verify the SLI query against
  real traffic; the freeze is only as good as the SLO. If a deploy genuinely must proceed during a
  burn (an emergency fix), that's the **break-glass** path
  ([kyverno-break-glass](kyverno-break-glass.md) covers the analogous policy override; for the
  rollout, an operator can `kubectl argo rollouts promote <app>` to skip the paused step).

## ArgoCD is fighting the canary (weights/selector revert mid-rollout, OutOfSync)

The Rollouts controller owns the Service `.spec.selector` and the HTTPRoute `backendRefs[].weight` at
runtime. If a sync is stomping them, the tenant Application is missing
**`RespectIgnoreDifferences=true`** (the `ignoreDifferences` alone is not enough). Verify in
`argocd-apps/delivery.tf` and re-apply `argocd-apps`. A purely **cosmetic** empty-diff OutOfSync under
ServerSideApply (foreign controllers co-own the fields) is the separate #894 follow-up — not a real
drift. See [debug-argocd-sync](debug-argocd-sync.md).

## The Rollouts web UI spins on "loading"

The native dashboard is namespace-scoped and **hangs on an empty default namespace** (its watch sends
no initial response). On a cluster where rollouts live in tenant namespaces, set
`dashboard_default_namespace` (argo-rollouts module) to a populated one. The platform-cluster UI is
empty until platform runs rollouts (tracked: brittle default #926, empty platform UI #927). The
cross-cluster *view* is the federated Grafana "Argo Rollouts" dashboard, not the native UI.

## Verifying the whole pipeline is healthy

```bash
kubectl -n <ns> get rollout,svc,pdb,httproute,analysistemplate    # the per-app shape
kubectl get clusterpolicy require-prod-replica-floor -o jsonpath='{.spec.rules[0].validate.failureAction}'  # Enforce
# rollout metrics scraping into Mimir:
#   count(rollout_info) via the federated datasource should be > 0 wherever rollouts run
```

## See also

- [How-to — extend & tune](../guides/zero-downtime/how-to-extend-platform.md) ·
  [Platform internals](../guides/zero-downtime/overview-platform.md)
- [debug-argocd-sync](debug-argocd-sync.md) · [kyverno-break-glass](kyverno-break-glass.md)
