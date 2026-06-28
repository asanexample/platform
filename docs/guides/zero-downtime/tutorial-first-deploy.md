# Tutorial — your first zero-downtime deploy

A guided first run: ship a small change and **watch the canary protect it**, step by step. By the end
you'll recognize what a healthy rollout looks like, where to watch it, and what the safety nets do —
without having to break anything.

**Prerequisites:** a Product on the paved road with a `*-prod` environment, on Tailscale, with
`kubectl argo rollouts` available (`kubectl krew install argo-rollouts`).

Throughout, substitute your own values: `<team>`, `<product>`, namespace `<team>-<product>-prod`,
rollout `app-<team>-<product>`.

## 1. Make a benign change

Make a visible-but-safe change in your app repo (a version string, a log line, a config default) and
open a PR. Keep it small — the point is to watch the *mechanism*, not the change.

## 2. Merge → the pipeline pins a digest

Merge to `main`. CI builds + cosign-signs the image, and the promote bot opens a **Release** PR that
pins the new digest. It auto-promotes through the lower stages; **prod is gated** — approve the prod
Release PR when you're ready.

## 3. Watch the canary start

As soon as the prod Release merges, start watching:

```bash
kubectl argo rollouts get rollout app-<team>-<product> -n <team>-<product>-prod --watch
```

You'll see the rollout move through, roughly:

```text
Status:        ॥ Paused
Strategy:      Canary
  Step:        1/5
  SetWeight:   25
  ActualWeight: 25
...
   ⟳ app-...-<new>  (canary)   25%
   ✔ app-...-<old>  (stable)   75%
```

What's happening: a **pre-flight error-budget freeze** ran first (it passed — your service was
healthy), then traffic split **25% to the new version**. The pause is the system holding the step
while the **metric gate** checks the canary's success rate.

## 4. Watch it promote

The gate samples your live success rate (Beyla RED metrics → Mimir → the SLO rules). While it stays
healthy, the rollout advances **25 → 50 → 100%** and then marks the new version **stable**:

```text
Status: ✔ Healthy
   ✔ app-...-<new>  (stable)  100%
```

That's a complete zero-downtime deploy: traffic shifted gradually, was watched the whole way, and no
user hit a broken version — while the old pods drained gracefully as they scaled down.

## 5. See it in the dashboards

- **Grafana → "Argo Rollouts"** — your rollout's status, replica counts, and the analysis-run
  (gate) verdicts. Switch the namespace dropdown to yours.
- **Grafana → SLO dashboard** — your burn rate and remaining error budget.
- **Rollouts web UI** — `https://rollouts.preprod.aws.refplat.org` (SSO): the same as the CLI,
  visually, with promote/abort buttons.

## 6. Understand the safety nets (no need to trigger them)

You just saw the *happy path*. Two things would have protected you otherwise — proven live on this
platform:

- **A bad version → automatic rollback.** If the canary's success rate had dropped, the metric gate
  would abort and shift traffic back to stable. Your users would have kept hitting the working
  version; you'd see `Status: ✖ Degraded` and the canary scaled to 0.
- **An already-unhealthy service → frozen.** If your service had *already* been burning its error
  budget when you deployed, the pre-flight freeze would have aborted the rollout before any traffic
  shifted — refusing to pile change onto an incident.

## What you learned

- A deploy is a **gradual, watched, reversible** traffic shift — not a replace.
- The **stable + canary** split is real weighted traffic; the gate reads your **SLO metrics**.
- Where to watch (CLI, Grafana, the web UI) and what healthy looks like.

## Next

- [How-to — ship, watch, roll back](how-to-ship.md) — the task recipes
- [Reference — automatic vs yours](reference-automatic-vs-yours.md)
- [Troubleshooting](troubleshooting-developers.md) — when a rollout doesn't do what you expect
