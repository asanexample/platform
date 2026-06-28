# FAQ — zero-downtime deployments

Quick answers; each links to the fuller doc.

## Do I have to do anything to get zero-downtime?

Almost nothing. Graceful drain, the PDB, topology spread, and the canary are all injected/generated
for you. Your part: **handle `SIGTERM`** and run **≥ 2 replicas in prod**. See the
[developer overview](overview-developers.md).

## Why is my prod deploy slower than it used to be?

Because it's now a **gated canary**, not a replace — traffic shifts 25 → 50 → 100% with a metric
check between steps. That deliberate pacing is what lets a bad version roll back before it reaches
everyone. Lower stages still deploy fast (trivial auto-promote).

## Canary or blue-green — which should I pick?

- **Canary** (default) — gradual weighted shift, limits blast radius, metric-gated. Good default for
  HTTP services with steady traffic.
- **Blue-green** — full new version up, health-checked, then an instant Service-selector cutover.
  Better for **low-traffic** services (no canary window to measure) or when you want zero traffic on
  a bad version. Set `deployStrategy` at scaffold time. See the [how-to](how-to-ship.md#choose-blue-green-instead-of-canary).

## What's the difference between the two gates?

The **error-budget freeze** is *pre-flight* — "is the service healthy enough to deploy at all?" (it
won't deploy into an active burn). The **metric gate** is *during the canary* — "is the new version
healthy?" (it rolls back a bad version). See [the two gates](overview-platform.md#the-two-gates).

## My deploy was frozen / rolled back — what now?

- **Frozen** (aborted at step 0): your service was already over budget. Check the SLO dashboard,
  resolve the degradation, redeploy.
- **Rolled back**: the new version degraded on real traffic. Fix forward, or re-promote the previous
  digest. Details in [troubleshooting](troubleshooting-developers.md).

## Can I customize my SLO or the gate thresholds?

Not yet. Every prod environment gets a fixed **99.9%** availability SLO and platform-default
thresholds. A per-Product/tier override is planned. If you truly need different behavior, raise it
with the platform team.

## Does this work for gRPC / non-HTTP services?

The metric gate reads HTTP-style RED metrics from Beyla. gRPC works (Beyla sees it); arbitrary TCP or
very low-traffic services may not produce enough signal to gate meaningfully — prefer **blue-green**
there, and remember the gate is **fail-open on no data** (it won't block, but it also can't protect
without traffic).

## What about StatefulSets and databases?

The availability defaults (PDB, drain, spread) apply to StatefulSets too. The **canary** strategy is
for stateless request workloads — don't weight-split a database. Stateful services use blue-green or
plain rolling updates; schema/data migrations are an app concern, not something the rollout handles.

## Why must prod run ≥ 2 replicas?

A single replica has nothing to fail over to — restart it and there's an outage, no matter how
graceful the drain. Prod **rejects < 2 at admission** (`require-prod-replica-floor`). Lower stages may
stay at 1 for cost.

## Is my low-traffic service actually protected?

The gates need traffic to evaluate. With too few requests the metric query returns nothing and the
gate **passes by default** (fail-open) — so it isn't really guarding. Use **blue-green** (a health
check, not a traffic window) for low-traffic services. See the "no data" section of
[troubleshooting](troubleshooting-developers.md).

## Where do I watch a rollout?

`kubectl argo rollouts get rollout <app> -n <ns> --watch`, the Grafana **Argo Rollouts** + **SLO**
dashboards, or the Rollouts **web UI** (`rollouts.preprod.aws.refplat.org`, SSO). See the
[how-to](how-to-ship.md#watch-a-rollout).

## Is the "paused" canary stuck?

Usually no — a prod canary pauses between steps and while the gate samples. It's only stuck if the
analysis shows `Failed`/`Error` or it far exceeds the configured pauses.

## See also

- [Developer overview](overview-developers.md) · [Glossary](glossary.md) ·
  [Troubleshooting](troubleshooting-developers.md)
