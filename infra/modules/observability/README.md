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

## Outputs

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
