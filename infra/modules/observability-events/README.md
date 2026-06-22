# observability-events

Observability **P4 (incident-response glue)** — a **Grafana Alloy** singleton Deployment that watches
**Kubernetes Events** cluster-wide (`loki.source.kubernetes_events`) and ships them to **Loki**, so events
are queryable next to logs/traces (`docs/plans/102-observability-stack.md`).

## Key decisions

- **Singleton Deployment** (`controller.replicas = 1`): the events watcher reads the Events API; more than
  one replica would duplicate every event into Loki. (Separate from the `observability-alloy` DaemonSet,
  which tails per-node pod logs — different controller + scope, so a distinct release.)
- **No AWS identity** — writes only to the in-cluster Loki gateway. Tenant `_platform` (per-team is P10).
- `rbac.create=true` — the Alloy ClusterRole already grants `events` get/list/watch. No phone-home; chart
  CRDs + config-reloader off.
- Gated by **`enable_log_pipeline`** (events are part of log collection; pairs with the pod-log DaemonSet
  and the Loki store).

## Verify

After apply: `kubectl -n observability get deploy alloy-events` (1/1), then in Grafana → Explore → Loki
query for the events stream (e.g. `{job=~".*events.*"}` or the namespace label) — Kubernetes events appear.
