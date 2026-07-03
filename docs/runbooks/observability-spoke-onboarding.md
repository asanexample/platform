# Onboarding an observability spoke (metrics, logs, traces)

How a workload cluster ships its metrics, logs, and traces to the central **platform hub**
(hub-and-spoke, #102 P10 / ADR-043/044). **preprod** is the first spoke, live for all three
signals (#625: metrics #150, logs #627, traces #628); this runbook is the template for the
next one.

## How it works (no proxy, no shared secret)

All three signals follow the **same structural pattern**: a spoke collector pushes to a
hub hostname; a write-only Gateway HTTPRoute **force-sets** `X-Scope-OrgID` to the spoke's
tenant, overwriting anything the client sends. Only the push path differs per signal.

```text
spoke (preprod)                                   platform hub (Cilium Gateway → store)
<collector> ──push──▶  https://<spoke>-<signal>.aws.refplat.org/<path>
  external label {cluster=<spoke>}                │  HTTPRoute (RequestHeaderModifier):
  no X-Scope-OrgID header                          │   • force-SETS X-Scope-OrgID=<tenant>  (overwrite)
                                                    │   • write-only path match             (no read exposed*)
                                                    ▼
                                              <store>-gateway → store (tenant=<spoke>)
```

\* Metrics is the one exception — its HTTPRoute can *optionally* also expose a read path
(`/prometheus`) per-tenant via `query_tenants`, when a spoke needs hub-evaluated ruler
alerts or cross-cluster reads (e.g. preprod's Argo Rollouts canary analysis, ADR-056 W8c).
Logs and traces are **always write-only** — no cross-cluster read path exists for them.

- **Tenant isolation is structural.** The hub Gateway force-sets `X-Scope-OrgID` per
  **hostname**, so a spoke physically cannot write to another tenant (e.g. `platform`) —
  even if it sends a forged header, the edge overwrites it.
- **Auth = network isolation.** The shared Gateway NLB is `internal` and reachable only over
  the VPC / Transit Gateway. **mTLS** (cert-manager client certs validated at the Gateway) is
  the planned P10.x hardening — see the #102 plan "Out of scope / follow-ups".
- **No secrets.** There is no shared token or cross-account Secrets Manager entry for any of
  the three signals — the design deliberately avoids one.
- **CiliumNetworkPolicy** (`fromEntities: ["ingress"]`) admits the Gateway Envoy past each
  store's `observability` default-deny namespace policy — one per signal's gateway/distributor.

### Metrics

```text
prometheus-agent ──remote_write──▶  https://<spoke>-mimir.aws.refplat.org/api/v1/push
```

Collector: `infra/modules/observability-prometheus-agent` (kube-prometheus-stack agent
mode). Write path: `/api/v1/push`. Optional read path: `/prometheus` (per-tenant, gated by
`query_tenants`). Backend: `mimir-gateway:80`.

### Logs

```text
Alloy (DaemonSet, per node) ──loki.write──▶  https://<spoke>-logs.aws.refplat.org/loki/api/v1/push
```

Collector: `infra/modules/observability-alloy` — same Alloy DaemonSet pattern as the hub's
own log collection (file-tailing `/var/log/pods/*` via a `spec.nodeName`-filtered
`discovery.kubernetes`), configured with a different `loki_push_url` (the spoke edge
hostname, not an in-cluster Service), `tenant_id` (belt-and-suspenders — the hub edge
overwrites it anyway), and `external_labels = { cluster = "<spoke>" }` so the hub can break
out/isolate log streams by cluster. Write path: `/loki/api/v1/push` (write-only, no read
path). Backend: `loki-gateway:80`.

### Traces

```text
app OTLP ──▶ OTel Collector (Deployment) ──otlphttp──▶  https://<spoke>-traces.aws.refplat.org
```

Collector: `infra/modules/observability-otel-collector`, deployed as a spoke-local gateway
Deployment. Apps in the spoke send OTLP to this collector, which exports via **OTLP/HTTP**
(`otlphttp`, not gRPC — the HTTPRoute terminates HTTP) to the hub Tempo edge, with a
`resource` processor upserting `cluster: "<spoke>"` on every span and `X-Scope-OrgID` set
on the exporter (again, belt-and-suspenders — the hub overwrites it). Write path:
`/v1/traces` (OTLP/HTTP, write-only). Backend: `tempo-distributor:4318`.

> **Gotcha (fixed, #1003):** the collector's metrics pipeline must export to Mimir via
> `otlphttp`, not `prometheusremotewrite` — the collector distro in use doesn't ship that
> exporter. If you're extending the collector config for a new signal, check the exporter
> exists in the built distro before wiring it.

## Where it's defined

| Concern | Path |
|---------|------|
| Hub edge — metrics (HTTPRoute + tenant overwrite + write/read + ingress CNP) | `infra/modules/observability-mimir/` (`spoke_ingest` input) |
| Hub edge — logs (HTTPRoute + tenant overwrite + write-only + ingress CNP) | `infra/modules/observability-loki/` (`spoke_ingest` input) |
| Hub edge — traces (HTTPRoute + tenant overwrite + write-only + ingress CNP) | `infra/modules/observability-tempo/` (`spoke_ingest` input) |
| Hub wiring (which spokes + tenants + datasources), all three signals | `infra/live/aws/platform/us-east-1/platform/{mimir,loki,tempo}/terragrunt.hcl` |
| Spoke collector modules | `infra/modules/observability-prometheus-agent/` (metrics) · `infra/modules/observability-alloy/` (logs) · `infra/modules/observability-otel-collector/` (traces) |
| Spoke units (preprod) | `infra/live/aws/preprod/us-east-1/platform/observability-spoke/` (metrics) · `.../observability-logs-spoke/` · `.../observability-traces-spoke/` |

## Add the next spoke (e.g. prod)

1. **Hub — metrics.** In the `mimir` unit, add the spoke to `spoke_ingest.tenants`
   (`prod = "prod"`) and to `extra_tenant_datasources` (`["preprod", "prod"]`). Apply the
   `mimir` unit. Optionally set `query_tenants` if the spoke needs hub-side canary reads or
   hub-evaluated ruler alerts.
2. **Hub — logs.** In the `loki` unit, add the spoke to `spoke_ingest.tenants` and
   `extra_tenant_datasources` the same way. Apply the `loki` unit.
3. **Hub — traces.** In the `tempo` unit, add the spoke to `spoke_ingest.tenants` and
   `extra_tenant_datasources`. Apply the `tempo` unit. Each apply publishes
   `<spoke>-<signal>.aws.refplat.org` (covered by the Gateway's `*.aws.refplat.org`
   wildcard cert — no DNS-01 wait) and adds a `<Signal> (<spoke>)` Grafana datasource.
4. **Spoke — metrics.** Copy the preprod `observability-spoke` unit into the new cluster's
   live tree, set `cluster_label` + `remote_write_url = https://<spoke>-mimir.aws.refplat.org/api/v1/push`.
5. **Spoke — logs.** Copy the preprod `observability-logs-spoke` unit, set
   `loki_push_url = https://<spoke>-logs.aws.refplat.org/loki/api/v1/push`, `tenant_id`,
   `external_labels = { cluster = "<spoke>" }`.
6. **Spoke — traces.** Copy the preprod `observability-traces-spoke` unit, set
   `tempo_otlp_endpoint = https://<spoke>-traces.aws.refplat.org`, `exporter_use_http = true`,
   `tenant_id`, `resource_attributes = { cluster = "<spoke>" }`.
7. The spoke cluster must reach the hub VPC privately (Transit Gateway / Tailscale) and
   Kyverno must exclude `observability` (it does by default).

You don't have to onboard all three signals together — each is independently wired via its
own module's `spoke_ingest` input and its own spoke unit.

## Verify

```bash
# Metrics: reachable + TLS valid (4xx on empty body), write-only (query path 404s)
curl -s -o /dev/null -w '%{http_code}\n' https://preprod-mimir.aws.refplat.org/api/v1/push        # 4xx
curl -s -o /dev/null -w '%{http_code}\n' https://preprod-mimir.aws.refplat.org/prometheus/api/v1/query?query=up  # 404 unless query_tenants includes preprod

# Logs: reachable + TLS valid, write-only
curl -s -o /dev/null -w '%{http_code}\n' https://preprod-logs.aws.refplat.org/loki/api/v1/push     # 4xx

# Traces: reachable + TLS valid, write-only
curl -s -o /dev/null -w '%{http_code}\n' https://preprod-traces.aws.refplat.org/v1/traces          # 4xx

# Remote-write health on the spoke metrics agent (0 failed samples):
#   prometheus_remote_storage_samples_failed_total  ~ 0
#   prometheus_remote_storage_samples_total         increasing

# In platform Grafana:
up{cluster="preprod"}                         # Mimir (preprod) — spoke targets up
count(kube_pod_info{cluster="preprod"})       # Mimir (preprod) — KSM from the spoke
{cluster="preprod"} | json                    # Loki (preprod) — spoke pod logs landing
{cluster="preprod"}                           # Tempo (preprod) — spoke traces landing (once workloads are instrumented, P7)
```

**Negative test (isolation), any signal:** temporarily set the spoke collector's header to
`X-Scope-OrgID: platform` (or `curl` a sample with that header). Query the `platform`
tenant for that data — it lands under **`preprod`**, not `platform` (the Gateway overwrote
the header). Revert.

## Troubleshooting

- **Spoke `curl` to any edge times out:** the spoke can't route to the hub internal NLB.
  Confirm the Transit Gateway attachment + route to the hub VPC CIDR, and that the spoke can
  resolve `*-<signal>.aws.refplat.org` (public recursive DNS → the internal NLB's private
  IPs).
- **`no org id` / 401-style errors on the hub (any signal):** the HTTPRoute's
  `RequestHeaderModifier` isn't applying — check the `<store>-spoke-<name>` HTTPRoute is
  `Accepted` on the Gateway and the matching `*-spoke-ingest-from-gateway`
  CiliumNetworkPolicy exists (the `observability` ns is default-deny).
- **No preprod series/logs/traces in Grafana but the collector looks healthy:** confirm the
  `<Signal> (preprod)` datasource's `X-Scope-OrgID` header is `preprod` (it queries the same
  in-cluster gateway/distributor as the hub datasource).
- **Traces collector exporting metrics too:** it must use `otlphttp`, not
  `prometheusremotewrite`, to reach Mimir — see the #1003 gotcha above.
- **Logs DaemonSet not tailing a node's pods:** confirm `discovery.kubernetes`'s
  `spec.nodeName` selector matches `$NODE_NAME` (a DaemonSet env var) — a missing/wrong
  selector causes duplicate ingestion (every pod tailed by every node) or none at all.
