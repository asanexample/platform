# Onboarding an observability spoke (metrics)

How a workload cluster ships its metrics to the central **platform hub's Mimir** (hub-and-spoke, #102 P10 /
ADR-043/044). **preprod** is the first spoke; this runbook is the template for the next one.

## How it works (no proxy, no shared secret)

```text
spoke (preprod)                                   platform hub (Cilium Gateway → Mimir)
prometheus-agent ──remote_write──▶  https://<spoke>-mimir.aws.refplat.org/api/v1/push
  externalLabels{cluster=<spoke>}                 │  HTTPRoute (RequestHeaderModifier):
  no X-Scope-OrgID header                         │   • force-SETS X-Scope-OrgID=<tenant>  (overwrite)
                                                  │   • path /api/v1/push only            (write-only)
                                                  ▼
                                            mimir-gateway → Mimir (tenant=<spoke>)
```

- **Tenant isolation is structural.** The hub Gateway force-sets `X-Scope-OrgID` per **hostname**, so a spoke
  physically cannot write to another tenant (e.g. `platform`) — even if it sends a forged header, the edge
  overwrites it. The query path is never exposed cross-cluster, so a spoke can't read any tenant either.
- **Auth = network isolation.** The shared Gateway NLB is `internal` and reachable only over the VPC /
  Transit Gateway. **mTLS** (cert-manager client certs validated at the Gateway) is the planned P10.x
  hardening — see the #102 plan "Out of scope / follow-ups".
- **No secrets.** There is no shared token or cross-account Secrets Manager entry — the design deliberately
  avoids one.

## Where it's defined

| Concern | Path |
|---------|------|
| Hub edge (HTTPRoute + tenant overwrite + write-only + ingress CNP) | `infra/modules/observability-mimir/` (`spoke_ingest` input) |
| Hub wiring (which spokes + datasources) | `infra/live/aws/platform/us-east-1/platform/mimir/terragrunt.hcl` |
| Spoke collector module | `infra/modules/observability-prometheus-agent/` |
| Spoke unit (preprod) | `infra/live/aws/preprod/us-east-1/platform/observability-spoke/` |

## Add the next spoke (e.g. prod)

1. **Hub** — in the `mimir` unit, add the spoke to `spoke_ingest.tenants` (`prod = "prod"`) and to
   `extra_tenant_datasources` (`["preprod", "prod"]`). Apply the `mimir` unit. This publishes
   `prod-mimir.aws.refplat.org` (covered by the Gateway's `*.aws.refplat.org` wildcard cert — no DNS-01 wait)
   and adds a `Mimir (prod)` Grafana datasource. (Optionally also set `query_tenants` / `ruler_tenants` on the
   `mimir` unit — the live config does — if the spoke needs hub-side canary reads or hub-evaluated ruler alerts.)
2. **Spoke** — copy the preprod `observability-spoke` unit into the new cluster's live tree, set
   `cluster_label` + `remote_write_url = https://prod-mimir.aws.refplat.org/api/v1/push`. Apply it.
3. The spoke cluster must reach the hub VPC privately (Transit Gateway / Tailscale) and Kyverno must exclude
   `observability` (it does by default).

## Verify

```bash
# From a spoke pod: reachable + TLS valid (Mimir 4xx on an empty body) and write-only (query path 404s).
curl -s -o /dev/null -w '%{http_code}\n' https://preprod-mimir.aws.refplat.org/api/v1/push        # 4xx
curl -s -o /dev/null -w '%{http_code}\n' https://preprod-mimir.aws.refplat.org/prometheus/api/v1/query?query=up  # 404

# Remote-write health on the spoke agent (0 failed samples):
#   prometheus_remote_storage_samples_failed_total  ~ 0
#   prometheus_remote_storage_samples_total         increasing

# In platform Grafana, the `Mimir (preprod)` datasource:
up{cluster="preprod"}                      # spoke targets up
count(kube_pod_info{cluster="preprod"})    # KSM from the spoke
```

**Negative test (isolation):** temporarily set the spoke agent's remote_write header to
`X-Scope-OrgID: platform` (or `curl` a sample with that header). Query the `platform` tenant — the series
land under **`preprod`**, not `platform` (the Gateway overwrote the header). Revert.

## Troubleshooting

- **Spoke `curl` to the edge times out:** the spoke can't route to the hub internal NLB. Confirm the Transit
  Gateway attachment + route to the hub VPC CIDR, and that the spoke can resolve `*-mimir.aws.refplat.org`
  (public recursive DNS → the internal NLB's private IPs).
- **`no org id` / 401-style Mimir errors on the hub:** the HTTPRoute's `RequestHeaderModifier` isn't applying
  — check the `mimir-spoke-<name>` HTTPRoute is `Accepted` on the Gateway and the `*-spoke-ingest-from-gateway`
  CiliumNetworkPolicy exists (the `observability` ns is default-deny).
- **No preprod series in Grafana but remote_write looks healthy:** confirm the `Mimir (preprod)` datasource's
  `X-Scope-OrgID` header is `preprod` (it queries the same in-cluster gateway as the hub datasource).
