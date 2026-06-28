# Reference — automatic vs your responsibility

A precise, look-up reference for what the platform injects/generates for zero-downtime and what you
must do yourself. For the narrative, see the [developer overview](overview-developers.md); to do a
task, the [how-to](how-to-ship.md).

## Injected or generated for you (do not author these)

| Thing | Value | Source | Notes |
|---|---|---|---|
| Container `lifecycle.preStop.sleep` | **10s** (native `SleepAction`) | Kyverno mutate `add-pod-defaults` | Holds the pod serving while the LB stops sending it new traffic |
| Pod `terminationGracePeriodSeconds` | **30** | Kyverno mutate `add-pod-defaults` | Must exceed preStop + your in-flight drain |
| `PodDisruptionBudget` | `maxUnavailable: 1` | Kyverno generate | One per Deployment/StatefulSet; GC'd with the workload |
| `topologySpreadConstraints` | zone + node, soft | Kyverno mutate `mutate-topology-spread` | Selector derived from your workload |
| Container `securityContext` | non-root hardened, drop ALL caps, `RuntimeDefault` | Kyverno mutate | (general policy, not zero-downtime-specific) |
| `automountServiceAccountToken` | `false` | Kyverno mutate | |
| The canary/blue-green **Rollout strategy** (prod) | stepped canary or BG cutover | scaffolder `deployStrategy` | See below |
| **Stable + canary Services** + weighted HTTPRoute (canary, prod) | — | Argo Rollouts + Gateway plugin | The controller owns their selectors/weights at runtime |
| The per-env **SLO** | **99.9%** HTTP availability | `observability-mimir` (registry-derived) | Drives the gates; **not currently customizable per app** |
| The two prod **gates** | error-budget freeze + canary metric gate | scaffolder prod overlay | See [the two gates](overview-platform.md#the-two-gates) |

## Your responsibility

| Thing | What to do | Enforced? |
|---|---|---|
| **Handle `SIGTERM`** | Stop accepting, drain in-flight, exit. Long-lived streams need app-level age limits / `GOAWAY` | No — your job (the injected preStop only buys the network-deprogram window) |
| **`replicas >= 2` in prod** | Set `replicas: 2` (or HPA `minReplicas: 2`) in `*-prod` | **Yes — rejected at admission** (`require-prod-replica-floor`, ADR-085). Lower stages may stay at 1 |
| **Deploy strategy** | `deployStrategy: canary` (default) or `bluegreen` at scaffold time | No — defaulted |
| `livenessProbe` + `readinessProbe` | Set both on every container | **Yes — rejected without them** (readiness is also what makes draining correct) |
| Resource `requests` + `limits` | cpu + memory on every container | **Yes — rejected without them** |

## The knobs

| Knob | Where | Values |
|---|---|---|
| `deployStrategy` | scaffolder (New Product) → shapes `k8s/overlays/prod` | `canary` (default) · `bluegreen` |
| Replica count | your `k8s/overlays/<stage>` (or HPA) | prod ≥ 2; lower stages your call |
| SLO objective | — | fixed **99.9%** today; a per-Product/tier override is planned, not yet available |

## Canary shape (prod / standard tier)

```text
strategy.canary:
  steps: [ setWeight 25 → pause → 50 → pause → 100 ]
  pre-flight: error-budget freeze   (abort if burn rate ≥ 2× budget)
  background: success-rate gate     (rollback if success rate < 95%, repeatedly — failureLimit 2)
```

Lower stages (dev/test/uat/staging) use the **base** Rollout's trivial auto-promote
(`setWeight: 100`, no gates) — zero-downtime via `maxSurge: 1` / `maxUnavailable: 0`, fast feedback.
**Blue-green** replaces the weighted steps with a single Service-selector cutover after a health
check (no Gateway plugin; zero traffic to a bad version).

## See also

- [`docs/examples/compliant-deployment.yaml`](../../examples/compliant-deployment.yaml) — a minimal
  compliant workload
- [Deploy an app to preprod](../../runbooks/deploy-app-preprod.md) — repo layout, manifests, the sync
- The [Kyverno policy catalog](../../architecture/kyverno-policy-catalog.md) — every admission rule,
  scope, and mode
