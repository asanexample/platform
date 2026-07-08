# observability-loki

Observability **P3a** — the multi-tenant **logs** store for the platform hub (`docs/plans/102-observability-stack.md`).
Deploys `grafana/loki` into the `observability` namespace, S3-backed, and registers a Grafana **Loki** datasource
(with a `trace_id` derived field that links a log line to its Tempo trace). Mirrors `observability-mimir` (P2); the
only structural difference is **identity**.

## Key decisions

- **EKS Pod Identity, not IRSA** (ADR-047). The module creates an IAM role trusting `pods.eks.amazonaws.com` and an
  `aws_eks_pod_identity_association` binding (`namespace`, ServiceAccount `loki`) → role. No OIDC provider inputs, no
  `eks.amazonaws.com/role-arn` annotation. (The rest of the observability stack has likewise migrated to EKS Pod
  Identity — ADR-047/#594.)
- **SingleBinary by default**, `SimpleScalable` (read/write/backend RF3) when `high_availability = true` — one toggle,
  same pattern as Mimir/Tempo.
- **S3 chunks** bucket created in-module (SSE-S3/AES256, versioned, lifecycle); IAM scoped to that bucket only.
- **Multitenancy on** (`auth_enabled`): `X-Scope-OrgID` required. In-cluster isolation rests on the `observability`
  namespace default-deny NetworkPolicy (tenant pods can't reach the store). Per-tenant limits double as the
  noisy-neighbor control. Retention (default 14d) enforced by the compactor.

## Key inputs

| Input | Default | Notes |
|-------|---------|-------|
| `cluster_name` | — | S3 + IAM naming + the Pod Identity association |
| `namespace` | `observability` | must pre-exist (observability module) |
| `helm_chart_version` | `7.0.0` | pinned in `_versions.hcl` |
| `high_availability` | `false` | SingleBinary ↔ SimpleScalable RF3 |
| `retention_period` | `336h` (14d) | compactor-enforced |
| `default_tenant_id` | `platform` | the hub's own logs |

## Gotchas

- The chart **requires** a `loki.schemaConfig` (tsdb / schema v13) — omitting it fails the release. Provided here.
- Collectors (Alloy) write to this store; they ship in the P3a log-pipeline unit, not here.

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
| [aws_eks_pod_identity_association.loki](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.loki](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.loki_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_s3_bucket.chunks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.chunks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.chunks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.chunks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.chunks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.chunks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [helm_release.loki](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.grafana_datasource](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_manifest.spoke_ingest_from_gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.spoke_ingest_route](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [aws_iam_policy_document.loki_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name (used for S3 bucket + IAM role naming + the Pod Identity association). | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region (S3 bucket region). | `string` | `"us-east-1"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_default_tenant_id"></a> [default\_tenant\_id](#input\_default\_tenant\_id) | Tenant ID (X-Scope-OrgID) the Grafana datasource queries with — the hub's own logs live here. | `string` | `"platform"` | no |
| <a name="input_enable_federated_datasource"></a> [enable\_federated\_datasource](#input\_enable\_federated\_datasource) | Provision a `Loki (all clusters)` datasource that queries ALL tenants at once (`X-Scope-OrgID: <default>|<extras…>`). Loki supports multi-tenant queries via the pipe-separated header natively — no server flag needed (unlike Mimir). Platform-admin overview lane (#626/#629). Off by default. | `bool` | `false` | no |
| <a name="input_extra_tenant_datasources"></a> [extra\_tenant\_datasources](#input\_extra\_tenant\_datasources) | Additional X-Scope-OrgID tenants to provision as Grafana datasources beyond default\_tenant\_id — e.g. ["preprod"] for the preprod logs spoke (#627). Each renders a `Loki (<tenant>)` datasource. | `list(string)` | `[]` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow Terraform to delete the (non-empty) Loki chunks bucket on destroy. true suits the rebuild-safe reference platform; set false to protect long-term logs. | `bool` | `true` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name. | `string` | `"loki"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | grafana/loki chart version (pinned in \_versions.hcl; resolved latest stable at authoring). | `string` | `"7.0.0"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name. Also used as fullnameOverride + the ServiceAccount name, so Service names are deterministic (e.g. <name>-gateway). | `string` | `"loki"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm repository URL. | `string` | `"https://grafana.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). Generous: the StatefulSet binds a WaitForFirstConsumer PVC on first schedule. | `number` | `1200` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | HA sizing: SimpleScalable (read/write/backend RF3) instead of the single-binary reference deployment, multi-replica gateway, memcached caches. false = single-binary minimal (reference cluster). | `bool` | `false` | no |
| <a name="input_ingestion_burst_size_mb"></a> [ingestion\_burst\_size\_mb](#input\_ingestion\_burst\_size\_mb) | Per-tenant ingestion burst size (MB). | `number` | `6` | no |
| <a name="input_ingestion_rate_mb"></a> [ingestion\_rate\_mb](#input\_ingestion\_rate\_mb) | Per-tenant sustained ingestion limit (MB/sec). | `number` | `4` | no |
| <a name="input_max_global_streams_per_user"></a> [max\_global\_streams\_per\_user](#input\_max\_global\_streams\_per\_user) | Per-tenant active streams cap (cardinality / memory / cost control). | `number` | `5000` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy Loki into. Defaults to the observability hub namespace so it shares Grafana's datasource sidecar and the existing default-deny NetworkPolicy isolation. Must already exist (created by the observability module). | `string` | `"observability"` | no |
| <a name="input_read_proxy_url"></a> [read\_proxy\_url](#input\_read\_proxy\_url) | P13 read-isolation enforcement (#590), identical to the mimir module: when set, the Grafana Loki datasources point at the loki-tenant-proxy with `oauthPassThru` (SSO identity decides scope) instead of the gateway with a fixed `X-Scope-OrgID`, and the per-cluster bypass datasources are dropped (only `loki` + `loki-all` remain, both proxy-fronted). Empty = direct datasources (pre-P13). | `string` | `""` | no |
| <a name="input_retention_period"></a> [retention\_period](#input\_retention\_period) | Loki per-tenant log retention (limits\_config.retention\_period), enforced by the compactor. Default 14d (336h). | `string` | `"336h"` | no |
| <a name="input_spoke_ingest"></a> [spoke\_ingest](#input\_spoke\_ingest) | Cross-cluster spoke LOG ingest via the shared Cilium Gateway (hub-and-spoke, #627). When `tenants` is<br/>non-empty this self-routes — per spoke — a write-only HTTPRoute at `<prefix>-logs.<domain>` that force-SETS<br/>`X-Scope-OrgID` to the mapped tenant (overwriting any client value — the cross-tenant spoofing guard) and<br/>matches only the Loki push path (`/loki/api/v1/push`), plus a CiliumNetworkPolicy admitting the Gateway<br/>Envoy's `ingress` identity to the Loki gateway. Empty `tenants` disables it. Auth = network isolation. | <pre>object({<br/>    domain            = string<br/>    gateway_name      = string<br/>    gateway_namespace = string<br/>    tenants           = map(string) # hostname-prefix => X-Scope-OrgID tenant<br/>  })</pre> | <pre>{<br/>  "domain": "",<br/>  "gateway_name": "",<br/>  "gateway_namespace": "",<br/>  "tenants": {}<br/>}</pre> | no |
| <a name="input_spoke_ingest_passthrough"></a> [spoke\_ingest\_passthrough](#input\_spoke\_ingest\_passthrough) | P13 per-team logs (#590): when true, the spoke ingest HTTPRoute STOPS force-setting `X-Scope-OrgID` and passes the spoke-supplied (per-team) tenant through to Loki. Required so preprod's per-team Alloy re-tenant survives the hub edge. Trades the cross-tenant write-spoofing guard for per-team writes — a deferred tradeoff hardened later by ingest mTLS (#590 Phase-4 D-2). Off = force-stamp (default, safe). | `bool` | `false` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the Loki PVC (WAL / local index scratch). | `string` | `"gp3"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to AWS resources (and sanitized into K8s labels). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_chunks_bucket_name"></a> [chunks\_bucket\_name](#output\_chunks\_bucket\_name) | Name of the S3 bucket holding Loki chunks. |
| <a name="output_loki_role_arn"></a> [loki\_role\_arn](#output\_loki\_role\_arn) | Pod Identity role ARN the Loki ServiceAccount assumes for S3 access (empty when not created). |
| <a name="output_push_endpoint"></a> [push\_endpoint](#output\_push\_endpoint) | In-cluster log push endpoint (gateway). Tenant via the X-Scope-OrgID header. |
| <a name="output_query_endpoint"></a> [query\_endpoint](#output\_query\_endpoint) | In-cluster Loki query endpoint (gateway) for the Grafana datasource. |
<!-- END_TF_DOCS -->