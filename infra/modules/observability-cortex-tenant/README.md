# observability-cortex-tenant (P13 metrics write-path re-tenant)

Deploys [cortex-tenant](https://github.com/blind-oracle/cortex-tenant) — a small write-path proxy
that splits a Prometheus `remote_write` request into **per-tenant sub-writes** based on a series
label. It is the write half of P13 per-team isolation (#590, ADR-043/044): the
[`tenant-proxy`](../../../services/tenant-proxy) enforces *reads* per team, and cortex-tenant is
what actually lands each team's metrics in its own Mimir tenant so there is something to enforce.

```text
Prometheus / spoke agent ──remote_write──▶ cortex-tenant ──┬─X-Scope-OrgID: alpha──▶ Mimir
  (relabel sets `tenant`=team-from-ns)                     ├─X-Scope-OrgID: bravo──▶ Mimir
                                                           └─X-Scope-OrgID: platform▶ Mimir (default: infra)
```

cortex-tenant reads the `tenant` label off each series, forwards the series to Mimir with the
matching `X-Scope-OrgID`, and **strips the label** (`label_remove`) so it is never stored. Series
with no `tenant` label go to `default_tenant` (`platform`) rather than being dropped.

## Status — built, not yet wired (default OFF)

`create = false` by default: **this module deploys nothing until a unit opts in**, and merging it
changes no live behaviour. The write-path cut-over is deliberately a separate, monitored step
because it reroutes the pipeline feeding every dashboard. The remaining wiring:

1. **Relabel** on the hub Prometheus + preprod agent write path — set `tenant` from the namespace:

   ```yaml
   # writeRelabelConfigs (Prometheus remote_write / agent). TWO steps — the first is load-bearing:
   # 1) FORCE tenant=platform for EVERY series, clobbering any `tenant` label a pod may have exposed.
   #    (Without this, a pod in an infra ns exposing tenant="alpha" would route itself into alpha —
   #    a spoof. The unconditional clobber is the anti-spoof; a single team-match rule is NOT enough.)
   - source_labels: [namespace]
     regex: '.*'
     target_label: tenant
     replacement: platform
   # 2) Override to the team for environment namespaces (<team>-<product>-<stage>). Infra namespaces
   #    (kube-system, observability, …) don't match → stay on the platform tenant from step 1.
   - source_labels: [namespace]
     regex: '([a-z0-9]+)-[a-z0-9-]+-(dev|test|uat|staging|prod)'
     target_label: tenant
     replacement: '$1'
   ```

   The relabel runs in the **platform-controlled** collector (hub Prometheus / spoke agent) and is
   derived from the k8s namespace, **overwriting** anything the pod sets — so a tenant workload cannot
   spoof its tenant on the normal scrape path. This is the anti-spoof property that lets the spoke
   Gateway edge stop force-stamping (Phase 4). NB: it only covers series that flow *through* the
   collector; a pod POSTing remote_write directly to the ingest edge bypasses it, which is why Phase 4
   also needs the egress NetworkPolicy + mTLS write-auth (see the #590 Phase-4 design comment).

2. **Reroute** `remote_write` from the Mimir gateway to this module's `write_url` output.

3. **Spoke edge (Phase 4):** the hub Cilium Gateway HTTPRoute currently force-SETS
   `X-Scope-OrgID: preprod` on the spoke ingest, overwriting anything upstream. For per-team it must
   become a passthrough (trust the collector-derived tenant). Until then, run cortex-tenant on the
   **hub** side of that edge, or relax the edge in lockstep.

4. **Read side:** widen the federated `Mimir (all clusters)` datasource to span the new team tenants
   so nothing disappears mid-migration, then point per-user Grafana at the `tenant-proxy`.

## Safe cut-over ordering

Because a re-tenant *moves* data (old cluster tenants `platform`/`preprod` → team tenants), do the
read side first: widen the federated datasource to include `alpha|bravo|platform|preprod`, verify
dashboards still resolve, THEN flip the write path. During the transition the federated view spans
both old and new tenants, so no series disappears. Once fully migrated, drop the drained cluster
tenant from the list.

## Config & toggle

Gated by `enable_per_team_tenants` (cost_profile-style). On the write path, so `replicas >= 2` and a
ServiceMonitor are on by default. Cheap: two small pods, no standing cloud infra.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cortex_tenant](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_mimir_push_url"></a> [mimir\_push\_url](#input\_mimir\_push\_url) | The Mimir distributor/gateway push endpoint cortex-tenant forwards to, e.g. http://mimir-gateway.observability.svc/api/v1/push. This is the SAME endpoint Prometheus writes to today — cortex-tenant simply inserts itself in front of it to split a write into per-tenant sub-writes. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created (the P13 write-path re-tenant toggle — enable\_per\_team\_tenants). | `bool` | `false` | no |
| <a name="input_create_service_monitor"></a> [create\_service\_monitor](#input\_create\_service\_monitor) | Create a ServiceMonitor so cortex-tenant's own metrics (throughput, per-tenant errors) are scraped — important, it sits on the write path. | `bool` | `true` | no |
| <a name="input_default_tenant"></a> [default\_tenant](#input\_default\_tenant) | Tenant used for any series missing the routing label — platform-owned infra (kube-system, observability, …) that isn't a team. Fail-safe: never leave empty (an empty default makes cortex-tenant 400 unlabeled series, dropping infra metrics). | `string` | `"platform"` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Chart name. | `string` | `"cortex-tenant"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | cortex-tenant chart version. | `string` | `"0.8.1"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | cortex-tenant chart repository. | `string` | `"https://blind-oracle.github.io/cortex-tenant"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds. | `number` | `600` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the shared observability namespace). | `string` | `"observability"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | cortex-tenant replicas. It is on the metrics write path, so run at least 2 for availability. | `number` | `2` | no |
| <a name="input_routing_label"></a> [routing\_label](#input\_routing\_label) | The series label cortex-tenant reads to pick the tenant (config.tenant.label). A platform-controlled relabel on the Prometheus/agent write path sets this to the team-from-namespace; cortex-tenant routes on it and strips it (label\_remove) so it is never stored. Must be a NORMAL label (not `__`-prefixed — Prometheus drops meta-labels before remote\_write, so cortex-tenant would never see it). | `string` | `"tenant"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_write_url"></a> [write\_url](#output\_write\_url) | cortex-tenant's remote\_write ingest endpoint (point Prometheus/agent here to re-tenant by team). Null when the module is disabled. |
<!-- END_TF_DOCS -->
