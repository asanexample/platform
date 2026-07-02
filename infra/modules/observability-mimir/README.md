# Observability — Mimir (Durable Metrics Store)

Deploys **Grafana Mimir** (`mimir-distributed` chart) as the hub's durable, multi-tenant, S3-backed
long-range metrics store, into the existing `observability` namespace (so it shares Grafana's datasource
sidecar and the namespace's default-deny NetworkPolicy isolation). The hub Prometheus `remote_write`s to it;
Grafana queries it as the default datasource. Includes the **S3 blocks bucket** (SSE-S3/AES256) and an
IAM role for Mimir's ServiceAccount, bound via **EKS Pod Identity** (ADR-047). This is **P2** of the observability stack (#102).

Runs in **classic architecture** (distributor → ingester gRPC, RF1) at minimal single-replica sizing — not
the chart's default Kafka ingest-storage. `multitenancy_enabled` is on; the hub's own metrics use tenant
`platform`.

Companion docs: [current-state architecture](../../../docs/architecture/observability-current-state.md) ·
[access runbook](../../../docs/runbooks/observability-access.md) ·
[troubleshooting runbook](../../../docs/runbooks/observability-troubleshooting.md).

## Usage

```hcl
module "mimir" {
  source = "../../modules/observability-mimir"

  cluster_name = "platform-use1-eks"
  aws_region   = "us-east-1"
  namespace    = "observability" # must exist (created by the observability module)

  helm_chart_version = "6.0.6"
  high_availability  = false  # single-replica; true => RF3 + zone-aware + caches + query-scheduler x2
  storage_class      = "gp3"  # ingester/store-gateway/compactor PVCs

  default_tenant_id     = "platform"
  datasource_is_default = true # Mimir is Grafana's default datasource

  tags = local.tags
}
```

## Key inputs

| Variable | Default | Purpose |
|----------|---------|---------|
| `high_availability` | `false` | RF3, zone-aware ingester/store-gateway, multi-replica read/write, memcached caches. |
| `storage_class` | `"gp3"` | StorageClass for the ingester/store-gateway/compactor StatefulSet PVCs. |
| `force_destroy` | `true` | Allow deleting the (non-empty) blocks bucket on destroy (rebuild-safe reference platform). |
| `blocks_retention` | `"365d"` | `compactor_blocks_retention_period` (per-tenant). `0` = keep forever. |
| `default_tenant_id` | `"platform"` | `X-Scope-OrgID` for the Grafana datasource (the hub's own metrics). |
| `datasource_is_default` | `false` | Mark the provisioned Mimir Grafana datasource the default. |
| `max_global_series_per_user` / `ingestion_rate` / `ingestion_burst_size` | 1.5M / 100k / 200k | Per-tenant limits (a noisy-neighbor security control). |

## Outputs

`blocks_bucket_name`, `mimir_role_arn`, `push_endpoint`
(`http://mimir-gateway.observability.svc/api/v1/push`), `query_endpoint` (`.../prometheus`).

## Hub-only extras (ruler · app SLOs · spoke ingest)

Beyond the base store, the hub Mimir also carries (all opt-in):

- **Ruler (P4)** — `enable_ruler` turns on Mimir's ruler for server-side recording/alerting rules;
  `ruler_tenants` scopes which tenants it evaluates and `ruler_alertmanager_url` points it at the hub
  Alertmanager.
- **Per-app SLO burn-rate rules (ADR-056)** — `app_slos` renders multi-window burn-rate alerting rules
  per application into the ruler.
- **Cross-cluster `spoke_ingest` (P10)** — authenticated remote-write ingest from observability spoke
  clusters into the hub store (the P10 multi-cluster path).

## Notes / gotchas

- **Security:** `X-Scope-OrgID` is a trust header, **not** auth. In-cluster isolation rests entirely on the
  `observability` namespace NetworkPolicy (tenant `team-*` pods can't reach Mimir). Mimir is **never** exposed
  via the Cilium Gateway (ClusterIP only). Cross-cluster authenticated ingest is P10.
- **Classic, not Kafka:** the 6.0.x chart defaults to Kafka ingest-storage. This module disables it
  (`kafka.enabled=false` + `ingest_storage.enabled=false` + `ingester.push_grpc_method_enabled=true`). A
  stray `mimir-kafka` pod means the override didn't take.
- **query-scheduler is required** — the chart wires querier/query-frontend to it and has no scheduler-less
  mode; disabling it breaks the read path (DNS failures). Kept on (single replica when not HA).
- **RF1 with one ingester** — `ingester.ring.replication_factor` must be 1 or writes are rejected.
- **AES256 (SSE-S3) bucket on purpose** — keeps the Mimir role free of KMS perms (an SSE-KMS bucket needs
  `kms:GenerateDataKey*`/`Decrypt` or writes fail) and avoids per-object KMS cost. `AWS-0132` is accepted in
  `.trivyignore.yaml` (CMK is the regulated-tier upgrade). `fullnameOverride=mimir` makes service names
  deterministic (`mimir-gateway`, …); `minio.enabled=false` (we use S3); `metaMonitoring.serviceMonitor`
  on (the hub Prometheus scrapes Mimir's own metrics).
- The `mimir-gateway` (nginx) ServiceMonitor target shows as **down** (404 on `/metrics`) — benign; nginx is
  a reverse proxy with no Prometheus endpoint.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.mimir](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.mimir](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.mimir_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.blocks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [helm_release.mimir](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.grafana_datasource](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_config_map_v1.ruler_rules](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_cron_job_v1.ruler_rules_sync](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/cron_job_v1) | resource |
| [kubernetes_manifest.cortex_tenant_ingest_from_gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.cortex_tenant_ingest_route](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.query_from_namespaces](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.spoke_ingest_from_gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.spoke_ingest_route](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [aws_iam_policy_document.mimir_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name (used for S3 bucket + IAM role naming). | `string` | n/a | yes |
| <a name="input_app_slos"></a> [app\_slos](#input\_app\_slos) | Per-app SLOs (ADR-056 / per-app SLOs → W11 error-budget freeze). Each entry renders Sloth-style multi-window<br/>burn-rate rules into an `app-slos` Mimir ruler namespace, loaded into the ruler tenant by the rules-sync. The<br/>`error_query`/`total_query` use a `{{window}}` placeholder (Beyla RED metrics filtered to the app's namespace).<br/>Produces `slo:current_burn_rate:ratio{sloth_id=...}` per app (the metric the freeze gate queries) + page/ticket<br/>burn alerts → hub Alertmanager. Usually registry-derived in the unit from the prod XEnvironment claims. | <pre>list(object({<br/>    id              = string # unique SLO id, e.g. "alpha-shop-prod-availability"<br/>    service         = string # service label, e.g. "app-alpha-shop"<br/>    slo_name        = string # e.g. "requests-availability"<br/>    objective       = number # e.g. 99.9<br/>    error_query     = string # PromQL numerator with {{window}}<br/>    total_query     = string # PromQL denominator with {{window}}<br/>    alert_name      = string # base alert name (CamelCase)<br/>    page_severity   = optional(string, "critical")<br/>    ticket_severity = optional(string, "warning")<br/>  }))</pre> | `[]` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region (S3 endpoint + bucket region). | `string` | `"us-east-1"` | no |
| <a name="input_blocks_retention"></a> [blocks\_retention](#input\_blocks\_retention) | Mimir per-tenant blocks retention (compactor\_blocks\_retention\_period). 0 = keep forever. | `string` | `"365d"` | no |
| <a name="input_cluster_label"></a> [cluster\_label](#input\_cluster\_label) | Clean `cluster` label for Mimir's own self-metrics (#630) — matches the hub's Prometheus externalLabels.cluster (e.g. `platform`) so they're attributed to the cluster they run on, not the chart's default (the release name `mimir`). Empty falls back to cluster\_name. | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_datasource_is_default"></a> [datasource\_is\_default](#input\_datasource\_is\_default) | Mark the provisioned Mimir Grafana datasource the default. Keep false until the kube-prometheus-stack Prometheus datasource is set non-default (avoids two Grafana defaults). | `bool` | `false` | no |
| <a name="input_default_tenant_id"></a> [default\_tenant\_id](#input\_default\_tenant\_id) | Tenant ID (X-Scope-OrgID) the Grafana datasource queries with — the hub's own metrics live here. | `string` | `"platform"` | no |
| <a name="input_enable_federated_datasource"></a> [enable\_federated\_datasource](#input\_enable\_federated\_datasource) | Enable Mimir read-path tenant federation (#626) and provision a single `Mimir (all clusters)` datasource that queries ALL tenants at once (`X-Scope-OrgID: <default>|<extras…>`), so one panel can span clusters. Write-isolation is unaffected (each spoke still writes only its own tenant at the Gateway edge). This is the PLATFORM-ADMIN overview lane — per-team scoping is P13 (#590). Off by default. | `bool` | `false` | no |
| <a name="input_enable_ruler"></a> [enable\_ruler](#input\_enable\_ruler) | Enable the Mimir ruler (P4) — evaluates alerting rules against EACH tenant's metrics (incl. the spokes' remote-written data) and sends fired alerts to ruler\_alertmanager\_url, so a spoke (e.g. preprod) failure produces an alert that reaches the hub Alertmanager → the triage agent (ADR-082). Rules are loaded per-tenant into ruler\_storage via mimirtool/the ruler API (the rules-sync). Hub only. Off by default. | `bool` | `false` | no |
| <a name="input_extra_tenant_datasources"></a> [extra\_tenant\_datasources](#input\_extra\_tenant\_datasources) | Additional X-Scope-OrgID tenants to provision as Grafana datasources beyond default\_tenant\_id — e.g. ["preprod"] for the preprod spoke (P10). Each renders a `Mimir (<tenant>)` datasource querying the in-cluster gateway with that tenant header. Read path only (Grafana is in-cluster); never the default. | `list(string)` | `[]` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow Terraform to delete the (non-empty) Mimir blocks bucket on destroy. true suits the rebuild-safe reference platform; set false to protect long-term metrics. | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name. | `string` | `"mimir-distributed"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | mimir-distributed chart version (6.0.x is the current stable line; 6.1.0-weekly tags are dev-only). | `string` | `"6.0.6"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name. Also used as fullnameOverride + the ServiceAccount name, so Service names are deterministic (e.g. <name>-gateway). | `string` | `"mimir"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm repository URL. | `string` | `"https://grafana.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). Generous: the StatefulSets bind WaitForFirstConsumer PVCs on first schedule. | `number` | `1200` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | HA sizing: RF3 + zone-aware ingester/store-gateway, multi-replica read/write path, memcached caches, query-scheduler, rollout-operator. false = single-replica minimal (reference cluster). | `bool` | `false` | no |
| <a name="input_ingestion_burst_size"></a> [ingestion\_burst\_size](#input\_ingestion\_burst\_size) | Per-tenant ingestion burst size (samples). | `number` | `200000` | no |
| <a name="input_ingestion_rate"></a> [ingestion\_rate](#input\_ingestion\_rate) | Per-tenant sustained samples/sec ingestion limit. | `number` | `100000` | no |
| <a name="input_max_global_exemplars_per_user"></a> [max\_global\_exemplars\_per\_user](#input\_max\_global\_exemplars\_per\_user) | Per-tenant in-memory exemplar storage (Mimir default 0 = OFF, exemplars discarded). >0 enables it so the Tempo metrics-generator's span-metrics exemplars (and Prometheus exemplars) are stored — the metric→trace link for APM (P6). | `number` | `100000` | no |
| <a name="input_max_global_series_per_user"></a> [max\_global\_series\_per\_user](#input\_max\_global\_series\_per\_user) | Per-tenant active series cap (cardinality / memory / cost control). | `number` | `1500000` | no |
| <a name="input_max_label_names_per_series"></a> [max\_label\_names\_per\_series](#input\_max\_label\_names\_per\_series) | Per-tenant cap on label names per series (Mimir default 30). Raised to admit Beyla's label-rich auto-instrumentation series (P7) — it stamps ~35+ k8s attributes, so the default silently discards its RED metrics. | `number` | `50` | no |
| <a name="input_mimirtool_version"></a> [mimirtool\_version](#input\_mimirtool\_version) | grafana/mimirtool image tag for the ruler rules-sync CronJob (match the Mimir app version). | `string` | `"3.0.4"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy Mimir into. Defaults to the observability hub namespace so Mimir shares Grafana's datasource sidecar and the existing default-deny NetworkPolicy isolation. The namespace must already exist (created by the observability module). | `string` | `"observability"` | no |
| <a name="input_query_consumer_namespaces"></a> [query\_consumer\_namespaces](#input\_query\_consumer\_namespaces) | Namespaces admitted to the Mimir gateway's query API directly in-cluster (e.g. backstage for the ADR-091 Cost tab). The observability ns default-denies ingress, so this is the allow. | `list(string)` | `[]` | no |
| <a name="input_ruler_alertmanager_url"></a> [ruler\_alertmanager\_url](#input\_ruler\_alertmanager\_url) | Alertmanager the Mimir ruler posts fired alerts to (the hub kube-prometheus-stack Alertmanager). Only used when enable\_ruler. | `string` | `"http://kube-prometheus-stack-alertmanager.observability.svc:9093"` | no |
| <a name="input_ruler_rules_sync_schedule"></a> [ruler\_rules\_sync\_schedule](#input\_ruler\_rules\_sync\_schedule) | Cron schedule for the ruler rules-sync (reconciles each tenant's ruler to the curated rules ConfigMap). | `string` | `"*/15 * * * *"` | no |
| <a name="input_ruler_tenants"></a> [ruler\_tenants](#input\_ruler\_tenants) | Spoke tenants (X-Scope-OrgID) to load the curated ruler alert rules into — the rules-sync CronJob runs `mimirtool rules sync` per tenant so each spoke's remote-written metrics produce alerts (→ hub Alertmanager → triage agent). Empty = no sync Job. Only used when enable\_ruler. | `list(string)` | `[]` | no |
| <a name="input_spoke_ingest"></a> [spoke\_ingest](#input\_spoke\_ingest) | Cross-cluster spoke metrics ingest via the shared Cilium Gateway (hub-and-spoke, ADR-044 / #102 P10).<br/>When `tenants` is non-empty this self-routes — for each spoke — a write-only HTTPRoute on the shared<br/>Gateway at `<prefix>-mimir.<domain>` that:<br/>  • force-SETS `X-Scope-OrgID` to the mapped tenant, overwriting any client value (the cross-tenant<br/>    spoofing guard — a spoke physically cannot write to another tenant), and<br/>  • matches `/api/v1/push` (write), and — for any prefix in `query_tenants` — ALSO `/prometheus` (read,<br/>    opt-in; powers spoke-side metric-gated canary, ADR-056 W8c). The read rule force-sets the SAME tenant<br/>    header, so a spoke can only ever query ITS OWN tenant — never the hub's or another spoke's data,<br/>plus a CiliumNetworkPolicy admitting the Gateway Envoy's reserved `ingress` identity to the Mimir gateway<br/>(the observability ns is default-deny). `domain`/`gateway_name`/`gateway_namespace` identify the shared<br/>Gateway. Empty `tenants` disables the edge. Auth = network isolation (internal NLB + TGW); mTLS is the<br/>documented P10.x hardening follow-up. | <pre>object({<br/>    domain            = string<br/>    gateway_name      = string<br/>    gateway_namespace = string<br/>    tenants           = map(string)               # hostname-prefix => X-Scope-OrgID tenant<br/>    query_tenants     = optional(set(string), []) # prefixes that ALSO get a read (/prometheus) route (W8c)<br/>    # P13 per-team re-tenant (#590): an ADDITIONAL write route at `<hostname_prefix>.<domain>` that forwards<br/>    # to cortex-tenant (no force-stamp — it strips any inbound X-Scope-OrgID and lets cortex-tenant derive the<br/>    # tenant per-series from the agent-set `route_tenant` label). Used for the additive DUAL-WRITE: the spoke<br/>    # keeps its existing force-stamped `<prefix>-mimir` route (the `preprod` tenant, unchanged) AND writes a<br/>    # second copy here → per-team tenants. Null = off.<br/>    cortex_tenant_route = optional(object({<br/>      hostname_prefix = string # e.g. "preprod-tenant" → preprod-tenant.<domain><br/>      service_name    = string # the cortex-tenant Service (e.g. "cortex-tenant")<br/>      service_port    = number # e.g. 8080<br/>    }))<br/>  })</pre> | <pre>{<br/>  "domain": "",<br/>  "gateway_name": "",<br/>  "gateway_namespace": "",<br/>  "query_tenants": [],<br/>  "tenants": {}<br/>}</pre> | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the ingester/store-gateway/compactor PVCs (WAL/local blocks scratch). | `string` | `"gp3"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to AWS resources (and sanitized into K8s labels). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_blocks_bucket_name"></a> [blocks\_bucket\_name](#output\_blocks\_bucket\_name) | Name of the S3 bucket holding Mimir blocks. |
| <a name="output_mimir_role_arn"></a> [mimir\_role\_arn](#output\_mimir\_role\_arn) | IAM role ARN bound to the Mimir ServiceAccount via EKS Pod Identity (empty when disabled). |
| <a name="output_push_endpoint"></a> [push\_endpoint](#output\_push\_endpoint) | In-cluster Prometheus remote\_write endpoint (gateway). Tenant via the X-Scope-OrgID header. |
| <a name="output_query_endpoint"></a> [query\_endpoint](#output\_query\_endpoint) | In-cluster Prometheus-API query endpoint (gateway) for the Grafana datasource. |
<!-- END_TF_DOCS -->