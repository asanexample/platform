# Troubleshooting — rollouts (for developers)

Symptom → cause → fix for the things you'll actually hit. Start every investigation with:

```bash
kubectl argo rollouts get rollout app-<team>-<product> -n <team>-<product>-prod --watch
```

It shows the current step, the canary/stable weights, and each AnalysisRun's verdict — which is
usually the whole answer.

## My rollout is "Paused" / stuck and not advancing

**Usually working as intended.** A prod canary pauses between steps and while the metric gate is
sampling. The `get rollout` output will show `Step: N/5` and a running analysis. Give it the step's
`pause` duration plus a gate interval. It's only a problem if the analysis shows `Error`/`Failed`
(below) or it sits far longer than the configured pauses.

## My deploy rolled back by itself (`Degraded`, canary scaled to 0)

The **canary metric gate** fired — your new version's success rate dropped below the threshold
(< 95%) repeatedly. Confirm:

```bash
kubectl argo rollouts get rollout app-<team>-<product> -n <ns>   # AnalysisRun: Failed
```

The new version is bad on real traffic. **Fix forward** (fix the bug, merge, the pipeline re-rolls)
or, if a previous version is fine, **re-promote the previous digest**
([how-to](how-to-ship.md#stop-or-roll-back)). The platform did its job — no users were left on the
broken version.

## My deploy never started — aborted at step 0

The **pre-flight error-budget freeze** fired: your service was *already* burning its error budget
faster than allowed (≥ 2×) when you deployed. The platform refused to add change to an in-progress
problem. Check **Grafana → SLO dashboard** for your burn rate. Resolve the underlying degradation
(or wait for the budget to recover); then the deploy proceeds normally. This is a feature, not a
bug — deploying into an incident usually makes it worse.

## The gate passed but my canary was actually broken — or shows "no data"

The gates are **fail-open on no data**: if the metric query returns nothing, the analysis passes
(`len(result) == 0` is a success condition). The common cause is **too little traffic to the canary**
to compute a rate — a low-traffic service can't be metric-gated meaningfully. Options: drive
representative traffic, lean on **blue-green** (a clean cutover after a health check rather than a
metric window), or rely on the readiness/liveness probes + auto-rollback on crashes. If you expected
data and there's none on a busy service, it's likely the SLO read path — raise it with the platform
team.

## My manifest was rejected at admission

Zero-downtime has hard requirements (ADR-085). The rejection message names the policy:

| Rejected by | Fix |
|---|---|
| `require-prod-replica-floor` | Set `replicas: 2` (or HPA `minReplicas: 2`) in `*-prod` |
| missing probes | Add `livenessProbe` + `readinessProbe` to every container (readiness is also what makes draining correct) |
| missing resources | Add cpu + memory `requests` + `limits` |
| image / hostname policies | Use your team's ECR image + an allowed HTTPRoute hostname |

See the [reference](reference-automatic-vs-yours.md#your-responsibility) and the
[Kyverno policy catalog](../../architecture/kyverno-policy-catalog.md).

## Traffic *did* drop during a deploy (it shouldn't)

Zero-downtime assumes two things only you can guarantee:

- **You handle `SIGTERM`.** If your app ignores it, in-flight requests are killed at the 30s grace
  deadline. Stop accepting, drain, exit. Long-lived streams (websockets/gRPC) need app-level age
  limits / `GOAWAY` — they won't drain on their own.
- **You run ≥ 2 replicas in prod.** A single replica has nothing to fail over to. (Prod now rejects
  < 2 at admission, so this is rare.)

If both hold and traffic still dropped during a *rollout*, capture the timing and the
`get rollout` output and raise it — that's a platform-side investigation.

## See also

- [How-to — ship, watch, roll back](how-to-ship.md)
- [Developer overview](overview-developers.md) · [Reference](reference-automatic-vs-yours.md)
