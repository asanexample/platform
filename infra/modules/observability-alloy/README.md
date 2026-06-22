# observability-alloy

Observability **P3a (log pipeline)** — a **Grafana Alloy DaemonSet** that tails each node's pod logs and ships
them to **Loki** (`docs/plans/102-observability-stack.md`). This is the collector half of P3a; the Loki store is
`observability-loki`.

## Key decisions

- **DaemonSet + file-tailing** (`controller.type=daemonset`, `alloy.mounts.varlog`): each Alloy reads only its own
  node's `/var/log/pods` (filtered via a `spec.nodeName` selector on `discovery.kubernetes`), so there's no
  duplicate ingestion. Logs are read from host files — **no `pods/log` RBAC** and **no AWS identity** needed (Alloy
  only writes to the in-cluster Loki gateway, so it never touches S3 and sidesteps the encryption SCP).
- **Tenant `_platform`** stamped on the write path (`loki.write … tenant_id`). Per-team derivation from the
  namespace is **P10**.
- **No phone-home** (`enableReporting=false`); chart CRDs off (`crds.create=false` — we run a plain collector).
- Gated by **`enable_log_pipeline`** (cost_profile per-knob override); points at the `observability-loki`
  `push_endpoint`.

## Inputs

| Input | Default | Notes |
|-------|---------|-------|
| `loki_push_url` | loki-gateway push URL | wire to the `observability-loki` `push_endpoint` output |
| `tenant_id` | `platform` | X-Scope-OrgID on platform logs |
| `helm_chart_version` | `1.10.0` | pinned in `_versions.hcl` |

## Verify

After apply: `kubectl -n observability get ds alloy` (one pod per node Ready), then in Grafana → Explore → Loki,
query `{namespace="observability"}` — platform logs appear. Trace→logs correlation lands with Tempo (P3b).
