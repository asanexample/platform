# How-to — ship, watch, and roll back a zero-downtime change

Task recipes for working with progressive delivery. Assumes you have a Product on the paved road
(scaffolded, CI signing, a prod environment). For the concepts, see the
[developer overview](overview-developers.md); for exact promotion steps, the
[promote-a-release runbook](../../runbooks/promote-a-release.md).

## Ship a change

You don't run a deploy — you **merge**, and the pipeline does the rest:

1. Merge to your app repo's `main`.
2. CI builds, **cosign-signs**, and the promote bot opens a **Release** PR pinning the new digest.
3. Promotion is **automatic up to staging**; **prod is gated** (a release-approver approves the prod
   Release).
4. On the prod Release merge, ArgoCD syncs and the **canary** runs: the pre-flight error-budget
   freeze, then `setWeight 25 → 50 → 100` with the background metric gate. It promotes only while
   healthy and **rolls back automatically** otherwise.

So shipping safely is the default — there's nothing extra to enable.

## Watch a rollout

```bash
# live status, steps, and analysis-run (gate) results
kubectl argo rollouts get rollout app-<team>-<product> -n <team>-<product>-prod --watch
```

- **Grafana → "Argo Rollouts"** — status/replicas/analysis across both clusters.
- **Grafana → SLO dashboard** — your burn rate + error budget (what the gates read).
- **Rollouts web UI** — `https://rollouts.preprod.aws.refplat.org` (Tailscale + SSO): live canary
  progression and manual promote/abort buttons.

## Stop or roll back

| Situation | What to do |
|---|---|
| The canary is **degrading** | Nothing — the metric gate aborts and rolls back to stable automatically |
| You want to **stop an in-flight** canary now | `kubectl argo rollouts abort rollout app-<team>-<product> -n <ns>` — reverts to stable. ⚠️ This is in-cluster only; ArgoCD will re-attempt the rollout while the **Release still pins the bad digest**, so follow with the durable step ↓ |
| **Durable rollback** (a bad version that's already promoted) | **Re-promote the previous digest** — revert the Release pin in git ([promote-a-release runbook](../../runbooks/promote-a-release.md)). ArgoCD syncs back to the known-good version |
| The canary is **paused and not moving** | Usually correct — it's waiting on a `pause` step or the metric gate. Check the analysis with `kubectl argo rollouts get rollout … --watch`; see [troubleshooting](troubleshooting-developers.md) |

> Why not `kubectl argo rollouts undo`? It works in-cluster but ArgoCD `selfHeal` reconciles back to
> the git-desired digest — in GitOps the durable rollback is **reverting the promotion**, not an
> imperative undo.

## Choose blue-green instead of canary

Set the strategy when you scaffold the Product:

- `deployStrategy: canary` (default) — gradual weighted shift, limits blast radius, metric-gated.
- `deployStrategy: bluegreen` — bring the new version up fully, health-check it, then **cut over the
  Service selector in one step**. No traffic reaches a bad version; no Gateway plugin needed.

It only affects the **prod** overlay (lower stages auto-promote either way). Changing it on an
existing Product is an `overlays/prod` edit.

## Customize your SLO / the gate threshold

Not yet — every prod environment gets a fixed **99.9%** availability SLO (auto-derived from your
HTTP metrics), and the gate thresholds are platform defaults. A per-Product/tier SLO override is
planned but not available today. If your service legitimately needs different behavior, that's a
platform conversation (see the break-glass runbook), not a per-app setting.

## See also

- [Reference — automatic vs your responsibility](reference-automatic-vs-yours.md)
- [Troubleshooting](troubleshooting-developers.md)
- [Tutorial — your first zero-downtime deploy](tutorial-first-deploy.md)
