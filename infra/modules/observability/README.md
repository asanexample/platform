# Observability (Hub — kube-prometheus-stack)

Deploys the central observability hub on a cluster: **kube-prometheus-stack** (Prometheus + Grafana +
Alertmanager + node-exporter + kube-state-metrics + prometheus-operator) in a dedicated `observability`
namespace. Grafana is hardened and served via the cluster's internal Gateway (Tailscale-only); Alertmanager
routes `critical` alerts to SNS via EKS Pod Identity; Prometheus optionally `remote_write`s to **Mimir** (the durable
store — see the [`observability-mimir`](../observability-mimir/README.md) module) and points Grafana's
default datasource at it. EKS-inaccurate scrape jobs and alert rule groups (scheduler/controller-manager/
etcd/kube-proxy) are disabled. This is **P1+** of the observability stack (#102).

Companion docs: [current-state architecture](../../../docs/architecture/observability-current-state.md) ·
[access runbook](../../../docs/runbooks/observability-access.md) ·
[troubleshooting runbook](../../../docs/runbooks/observability-troubleshooting.md).

## Usage

```hcl
module "observability" {
  source = "../../modules/observability"

  cluster_name = "platform-use1-eks"
  aws_region   = "us-east-1"

  helm_chart_version = "86.1.0"
  high_availability  = false # single-replica reference cluster; true => Prom x2 / AM x3 / Grafana x2 + PDBs

  # Durable storage (needs a default StorageClass, e.g. gp3 from the eks-addons unit)
  use_persistent_storage = true
  storage_class          = "gp3"

  # Alertmanager -> SNS (critical alerts -> email). The SNS-publish role (Pod Identity) is created when alerts_topic_arn is set.
  alerts_topic_arn  = "arn:aws:sns:us-east-1:829808296602:platform-alerts"

  # Ship to Mimir for durable, long-range storage (empty = local Prometheus only).
  # Setting this also makes the Mimir datasource Grafana's default.
  mimir_remote_write_url = "http://mimir-gateway.observability.svc/api/v1/push"
  mimir_tenant_id        = "platform"

  grafana_hostname = "grafana.aws.refplat.org"
  tags             = local.tags
}
```

## Key inputs

| Variable | Default | Purpose |
|----------|---------|---------|
| `high_availability` | `false` | Prom×2 / AM×3 / Grafana×2 + anti-affinity + PDBs. Needs ≥3 nodes / 2–3 AZs. |
| `use_persistent_storage` / `storage_class` | `false` / `""` | Back Prometheus + Alertmanager with PVCs. `false` = emptyDir (interim). |
| `prometheus_retention` | `"15d"` | Local retention — short by design (Mimir is the durable store). |
| `alerts_topic_arn` | `""` | Set ⇒ Alertmanager SNS-publish role via EKS Pod Identity + `sns_configs` receiver (incl. `kms:GenerateDataKey*` for the SSE-KMS topic). |
| `mimir_remote_write_url` / `mimir_tenant_id` | `""` / `"platform"` | When set: Prometheus `remoteWrite` + `externalLabels{cluster}`, and the bundled Prometheus datasource is no longer Grafana's default. |
| `grafana_hostname` | `grafana.aws.refplat.org` | `root_url` + cookie domain; the gateway HTTPRoute backend is `<release>-grafana`. |
| `secret_path_prefix` | `"platform"` | Grafana admin credential at `<prefix>/observability/grafana-admin` (Secrets Manager). |

## Key outputs

`namespace`, `grafana_service_name` (gateway HTTPRoute backend), `grafana_admin_secret_arn`,
`alertmanager_role_arn`.

## Notes / gotchas

- **Namespace** is created by this module (not the chart) so it carries PSA `enforce: privileged`
  (node-exporter needs hostNetwork) and **no** tenant label. The chart's `create_namespace` is off.
- **Grafana ingress** requires a **CiliumNetworkPolicy** (`fromEntities: ["ingress"]`) — the Cilium gateway
  Envoy's reserved `ingress` identity can't be matched by a standard k8s NetworkPolicy. The namespace is
  otherwise default-deny ingress + allow-intra-namespace.
- **EKS accuracy:** `kubeScheduler`/`kubeControllerManager`/`kubeEtcd`/`kubeProxy` scrape jobs **and** their
  `defaultRules` groups are disabled (managed control plane unscrapeable; Cilium replaces kube-proxy).
- `serviceMonitorSelectorNilUsesHelmValues=false` ⇒ Prometheus scrapes **all** ServiceMonitors cluster-wide.
- **emptyDir → PVC is an in-place StatefulSet recreation** (operator-driven, immutable volumeClaimTemplates).
  It deadlocks `helm --wait`; do that migration with `helm_wait=false`. See the troubleshooting runbook.
- Dashboards are provisioned as code from `dashboards/*.json` (Grafana sidecar ConfigMaps).
- **Alerting receivers (SNS / Slack / PagerDuty / triage).** Beyond the SNS receiver, Alertmanager can
  also fan out to **Slack** (`slack_webhook_secret_name` / `slack_channel`), **PagerDuty**
  (`pagerduty_routing_key_secret_name`), and the **triage-agent** webhook (`triage_webhook_url`, ADR-082)
  — all opt-in, wired only when their inputs are set.
- **Grafana SSO (Keycloak OIDC).** Set `grafana_oidc_issuer` / `grafana_oidc_client_id` /
  `grafana_oidc_secret_manager_key` (+ `grafana_oidc_role_attribute_path` for role mapping) to log into
  Grafana via Keycloak (#592); the client secret is projected from Secrets Manager. Admin-password auth
  remains the fallback.
- **Grafana CloudWatch datasource (P5a).** `cloudwatch_enabled = true` adds a CloudWatch datasource (read
  access via the same Pod Identity path) so AWS metrics are queryable alongside the Prometheus/Mimir data.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.alertmanager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_eks_pod_identity_association.grafana_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.alertmanager](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.grafana_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.alertmanager_sns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.grafana_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_secretsmanager_secret.grafana_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.grafana_admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [helm_release.kube_prometheus_stack](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_config_map_v1.dashboards](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_manifest.alertmanager_pagerduty](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.alertmanager_slack_webhook](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.allow_grafana_from_gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.grafana_oidc_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_network_policy_v1.allow_intra_namespace](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.allow_platform_agent_read](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.default_deny_ingress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_secret_v1.grafana_admin](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [null_resource.namespace_drain](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.grafana_admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_iam_policy_document.alertmanager_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.grafana_cloudwatch_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [kubernetes_service_v1.gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/service_v1) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name (for resource naming / labels). | `string` | n/a | yes |
| <a name="input_alerts_topic_arn"></a> [alerts\_topic\_arn](#input\_alerts\_topic\_arn) | SNS topic ARN for critical alerts. When set, the Alertmanager SA gets a role with sns:Publish (bound via EKS Pod Identity) and the Alertmanager config gains an sns\_configs receiver. | `string` | `""` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region (for the Alertmanager → SNS sigv4 signer). | `string` | `"us-east-1"` | no |
| <a name="input_cloudwatch_enabled"></a> [cloudwatch\_enabled](#input\_cloudwatch\_enabled) | Add a Grafana CloudWatch datasource (query-time, zero-storage AWS-resource metrics) + grant the Grafana ServiceAccount CloudWatch read via EKS Pod Identity. Covers NLB/S3/TGW/NAT/Route53/EKS etc. with no exporter. #102 P5a. | `bool` | `false` | no |
| <a name="input_cluster_label"></a> [cluster\_label](#input\_cluster\_label) | Value of the `cluster` external label stamped on every metric — the multi-cluster dimension. Use a clean, consistent name matching the tenant/env (e.g. `platform`), so the single pane reads `platform`/`preprod`, not the raw EKS cluster IDs. Empty falls back to cluster\_name (the EKS cluster ID). | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_deployer_role_arn"></a> [deployer\_role\_arn](#input\_deployer\_role\_arn) | IAM role ARN to assume for the destroy-time namespace drain (the PlatformDeployer) | `string` | `""` | no |
| <a name="input_finalizer_clear_script"></a> [finalizer\_clear\_script](#input\_finalizer\_clear\_script) | Absolute path to scripts/k8s-finalizer-clear.sh (passed from the unit via get\_repo\_root()) | `string` | `""` | no |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace of the Gateway-API gateway (Envoy) allowed to reach Grafana ingress. Empty = allow ingress to Grafana from all namespaces (still default-deny for the rest of the ns). | `string` | `""` | no |
| <a name="input_gateway_service_name"></a> [gateway\_service\_name](#input\_gateway\_service\_name) | Cilium gateway LoadBalancer Service whose ClusterIP backs oidc\_gateway\_alias\_host. | `string` | `"cilium-gateway-platform-gateway"` | no |
| <a name="input_gateway_service_namespace"></a> [gateway\_service\_namespace](#input\_gateway\_service\_namespace) | Namespace of the Cilium gateway Service. | `string` | `"default"` | no |
| <a name="input_grafana_hostname"></a> [grafana\_hostname](#input\_grafana\_hostname) | External hostname Grafana is served at (gateway HTTPRoute). Sets grafana.ini root\_url and the cookie domain. | `string` | `"grafana.aws.refplat.org"` | no |
| <a name="input_grafana_oidc_client_id"></a> [grafana\_oidc\_client\_id](#input\_grafana\_oidc\_client\_id) | Grafana OIDC client\_id in Keycloak. | `string` | `"grafana"` | no |
| <a name="input_grafana_oidc_issuer"></a> [grafana\_oidc\_issuer](#input\_grafana\_oidc\_issuer) | Keycloak OIDC issuer URL (e.g. https://keycloak.aws.refplat.org/realms/platform). Empty disables Grafana SSO (admin-password only). | `string` | `""` | no |
| <a name="input_grafana_oidc_role_attribute_path"></a> [grafana\_oidc\_role\_attribute\_path](#input\_grafana\_oidc\_role\_attribute\_path) | Grafana role mapping (JMESPath over the token's `groups` claim). Default: platform-admins → Admin, any other authenticated user → Viewer. Per-team Editor scoping is P13 (#590). | `string` | `"contains(groups[*], 'platform-admins') && 'Admin' || 'Viewer'"` | no |
| <a name="input_grafana_oidc_secret_manager_key"></a> [grafana\_oidc\_secret\_manager\_key](#input\_grafana\_oidc\_secret\_manager\_key) | AWS Secrets Manager key holding the Grafana OIDC client secret (keycloak-config writes platform/keycloak/grafana-oidc, JSON property `client-secret`). Synced to a K8s secret via ExternalSecret, injected as GF\_AUTH\_GENERIC\_OAUTH\_CLIENT\_SECRET. | `string` | `""` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Chart name. | `string` | `"kube-prometheus-stack"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | kube-prometheus-stack chart version (latest GA — resolve at apply time). | `string` | `"86.1.0"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name. Pinned so the Grafana Service (<release>-grafana) and the Alertmanager ServiceAccount (<release>-alertmanager) names are deterministic for the gateway route and the Pod Identity association (ADR-047). | `string` | `"kube-prometheus-stack"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | kube-prometheus-stack chart repository. | `string` | `"https://prometheus-community.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Timeout for Helm operations in seconds. | `number` | `900` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Whether to wait for the Helm release to become ready. | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | HA mode: Prometheus ×2, Alertmanager ×3, Grafana ×2 with anti-affinity + PDB. false = single-replica (cost-optimized) — fine for the reference clusters. Needs >=3 nodes across >=2-3 AZs when true. | `bool` | `false` | no |
| <a name="input_mimir_remote_write_url"></a> [mimir\_remote\_write\_url](#input\_mimir\_remote\_write\_url) | Mimir push endpoint for Prometheus remote\_write (e.g. http://mimir-gateway.observability.svc/api/v1/push). Empty = no remote\_write (P1 behaviour). When set, the bundled Prometheus datasource is no longer Grafana's default (the Mimir datasource takes over). | `string` | `""` | no |
| <a name="input_mimir_tenant_id"></a> [mimir\_tenant\_id](#input\_mimir\_tenant\_id) | X-Scope-OrgID the hub's own metrics are written under (and queried with). | `string` | `"platform"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for the observability hub. Created by this module (not the chart) so it carries the right Pod Security Admission label for node-exporter. | `string` | `"observability"` | no |
| <a name="input_oidc_gateway_alias_host"></a> [oidc\_gateway\_alias\_host](#input\_oidc\_gateway\_alias\_host) | Split-horizon host-alias: the OIDC issuer hostname (keycloak.aws.refplat.org) pinned to the Cilium Gateway Envoy ClusterIP, so Grafana's backend token/userinfo calls reach Keycloak via the gateway directly — NOT the internal NLB (which a pod can't reliably hairpin to). Mirrors Backstage. Empty disables the alias. | `string` | `""` | no |
| <a name="input_pagerduty_routing_key_secret_name"></a> [pagerduty\_routing\_key\_secret\_name](#input\_pagerduty\_routing\_key\_secret\_name) | AWS Secrets Manager secret name holding the PagerDuty Events API v2 routing/integration key (JSON property 'routingKey'). Empty disables the PagerDuty receiver. Synced to Alertmanager via External Secrets — never enters Terraform state or helm values. Critical alerts page PagerDuty. | `string` | `""` | no |
| <a name="input_prometheus_retention"></a> [prometheus\_retention](#input\_prometheus\_retention) | Local Prometheus retention. Interim only — Mimir becomes the durable store at P2; kept short here. | `string` | `"15d"` | no |
| <a name="input_secret_path_prefix"></a> [secret\_path\_prefix](#input\_secret\_path\_prefix) | Secrets Manager path prefix for the generated Grafana admin credential (stored at <prefix>/observability/grafana-admin for human retrieval; the k8s Secret is created directly by TF since the password is TF-generated). | `string` | `"platform"` | no |
| <a name="input_secret_recovery_window_days"></a> [secret\_recovery\_window\_days](#input\_secret\_recovery\_window\_days) | Secrets Manager recovery window for the generated Grafana admin secret. 0 = force-delete (setup-friendly); raise for prod. | `number` | `0` | no |
| <a name="input_secret_store_name"></a> [secret\_store\_name](#input\_secret\_store\_name) | Name of the External Secrets ClusterSecretStore (AWS Secrets Manager). | `string` | `"aws-secrets-manager"` | no |
| <a name="input_slack_channel"></a> [slack\_channel](#input\_slack\_channel) | Slack channel for alerts (the incoming webhook is bound to its own channel; this is informational/override). | `string` | `"#platform-alerts"` | no |
| <a name="input_slack_webhook_secret_name"></a> [slack\_webhook\_secret\_name](#input\_slack\_webhook\_secret\_name) | AWS Secrets Manager secret name holding the Slack incoming-webhook URL (JSON property 'url'). Empty disables the Slack receiver (SNS-only). Synced to Alertmanager via External Secrets — never enters Terraform state or helm values. | `string` | `""` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for Prometheus/Alertmanager PVCs when use\_persistent\_storage = true. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply (sanitized to RFC-1123 for K8s labels). | `map(string)` | `{}` | no |
| <a name="input_triage_webhook_url"></a> [triage\_webhook\_url](#input\_triage\_webhook\_url) | ADR-082: the triage agent's in-cluster webhook URL (e.g. http://triage-copilot-server.platform-agent-triage-copilot.svc.cluster.local/webhook). When set, a curated alert subset (critical) is fanned to the agent ADDITIVELY (continue=true, the alert still reaches SNS/Slack). Empty disables the triage receiver/route. | `string` | `""` | no |
| <a name="input_use_persistent_storage"></a> [use\_persistent\_storage](#input\_use\_persistent\_storage) | Back Prometheus/Alertmanager with PVCs (needs a default StorageClass). false = emptyDir (acceptable for the interim P1 local Prometheus; Mimir is durable from P2). | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alertmanager_role_arn"></a> [alertmanager\_role\_arn](#output\_alertmanager\_role\_arn) | IAM role ARN bound to the Alertmanager SA via EKS Pod Identity for SNS publish (empty when no alerts topic). |
| <a name="output_grafana_admin_secret_arn"></a> [grafana\_admin\_secret\_arn](#output\_grafana\_admin\_secret\_arn) | Secrets Manager ARN holding the generated Grafana admin credential (retrieve to log in until SSO lands). |
| <a name="output_grafana_service_name"></a> [grafana\_service\_name](#output\_grafana\_service\_name) | Grafana Service name (for the gateway HTTPRoute backend). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Observability namespace. |
<!-- END_TF_DOCS -->