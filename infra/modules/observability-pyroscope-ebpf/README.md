# observability-pyroscope-ebpf

**Zero-code continuous profiling** (#102 P8b) — a privileged **Alloy** DaemonSet that attaches **eBPF** on
each node and CPU-profiles the running processes, pushing flame-graph profiles to **Pyroscope**. No app
changes — it dogfoods every platform component.

## What it deploys

- **grafana/alloy** as a privileged DaemonSet (`hostPID` + `privileged`, like the Beyla eBPF agent; the
  observability namespace is PSA `privileged`).
- River pipeline: `discovery.kubernetes` (pods) → `discovery.relabel` (sets `service_name = <ns>/<pod>`) →
  `pyroscope.ebpf` → `pyroscope.write` (to Pyroscope, stamped with the tenant `X-Scope-OrgID`).

## Correlation

Together with the Tempo datasource's `tracesToProfilesV2` link, a span in a trace jumps to the matching
flame graph (by `service_name`). See `observability-pyroscope` (the store) and `observability-tempo`.
