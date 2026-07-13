# observability-prometheus-agent

A **lightweight metrics spoke** for the hub-and-spoke observability stack (#102 P10). Runs
**kube-prometheus-stack in agent mode** — scrape-and-ship only: no Grafana, no Alertmanager, no rule
evaluation, no local query/TSDB. It scrapes its own cluster (kubelet/cAdvisor, kube-state-metrics,
node-exporter, and any cluster `ServiceMonitor`/`PodMonitor`) and `remote_write`s to the **platform hub's
Mimir** over the private network.

Reusing the same chart as the hub means metric names + labels match, so the hub's existing dashboards work
for the spoke with no extra wiring.

## How it fits

```text
spoke cluster (e.g. preprod)                         platform hub
┌────────────────────────────────┐                  ┌──────────────────────────────┐
│ prometheus-agent (this module) │ remote_write     │ Cilium Gateway (HTTPRoute)    │
│  scrape kubelet/KSM/node-exp   │ ───────────────▶ │  force-sets X-Scope-OrgID     │
│  externalLabels{cluster=...}   │  https://<spoke> │  + write-only /api/v1/push    │
└────────────────────────────────┘  -mimir.<domain> │         │                     │
                                                     │         ▼  mimir-gateway      │
                                                     │       Mimir (tenant=<spoke>)  │
                                                     └──────────────────────────────┘
```

- The agent sends **no** `X-Scope-OrgID` — the hub Gateway force-sets it per-hostname, so a spoke physically
  cannot write to another tenant (the ADR-044 cross-tenant-spoofing guard). See the hub's
  `observability-mimir` module `spoke_ingest` input.
- **Auth = network isolation** (internal NLB reachable only over the VPC/Transit Gateway). mTLS is the
  documented P10.x hardening follow-up.
- The WAL is on a gp3 PVC so buffered samples survive a pod restart during a hub outage (agent-side
  buffering).

## Namespace & policy

The `observability` namespace is created here (not by the chart) with PSA `privileged` (node-exporter needs
host access) and **no** tenant label, plus a `default-deny-ingress` + `allow-intra-namespace` NetworkPolicy.
Kyverno already excludes `observability` by default, so no spoke policy change is needed.

## Usage

```hcl
module "spoke" {
  source = "../../modules/observability-prometheus-agent"

  cluster_name     = "preprod-eks"
  cluster_label    = "preprod"
  remote_write_url = "https://preprod-mimir.aws.refplat.org/api/v1/push"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.agent](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.crossplane_pod_monitor](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.crossplane_provider_pod_monitor](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_network_policy_v1.allow_intra_namespace](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.allow_otlp_from_environments](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |
| [kubernetes_network_policy_v1.default_deny_ingress](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/network_policy_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Spoke EKS cluster name (resource naming / fallback cluster label). | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region (informational; the agent holds no AWS creds — it only scrapes + remote\_writes). | `string` | `"us-east-1"` | no |
| <a name="input_cluster_label"></a> [cluster\_label](#input\_cluster\_label) | Value of the `cluster` external label stamped on every series (so the hub can isolate this spoke, e.g. `up{cluster="preprod"}`). Falls back to cluster\_name when empty. | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_enable_crossplane_pod_monitor"></a> [enable\_crossplane\_pod\_monitor](#input\_enable\_crossplane\_pod\_monitor) | Create a PodMonitor scraping the Crossplane core controller on THIS cluster (crossplane-system, app=crossplane, named `metrics` port) — mirrors the hub `observability` module's variable of the same name. Enable where crossplane + this spoke co-reside (e.g. preprod, where XEnvironment claims actually reconcile, ADR-048). | `bool` | `false` | no |
| <a name="input_enable_crossplane_provider_pod_monitor"></a> [enable\_crossplane\_provider\_pod\_monitor](#input\_enable\_crossplane\_provider\_pod\_monitor) | Create a PodMonitor scraping Crossplane PROVIDER pods on THIS cluster (provider-aws-*, provider-family-aws, provider-kubernetes — any pod carrying `pkg.crossplane.io/provider`, named `metrics` port) — mirrors the hub `observability` module's variable of the same name. Covers composed-resource reconciliation, distinct from the core-controller PodMonitor above. | `bool` | `false` | no |
| <a name="input_enable_otlp_ingress"></a> [enable\_otlp\_ingress](#input\_enable\_otlp\_ingress) | Add an ingress NetworkPolicy allowing OTLP (4317/4318) to the OTel collector from namespaces labeled platform.refplat.org/otel-export=true. Enable on spokes where tenant apps export traces via the OTel SDK (P14 log→trace). Off by default; the collector namespace otherwise default-denies cross-namespace ingress. | `bool` | `false` | no |
| <a name="input_enable_team_budget_metric"></a> [enable\_team\_budget\_metric](#input\_enable\_team\_budget\_metric) | Configure kube-state-metrics CustomResourceState to emit team\_budget\_monthly\_usd{team} from the Team CR (ADR-091). Enable only on the spoke that runs the env-API Team CRD (preprod). | `bool` | `false` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name. kube-prometheus-stack in agent mode — same chart as the hub, so metric names/labels match and the hub dashboards work for this spoke. | `string` | `"kube-prometheus-stack"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | kube-prometheus-stack chart version (pin from \_versions.hcl; reuses the hub's pin). | `string` | `"87.5.0"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name (also the chart fullname prefix). | `string` | `"prometheus-agent"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm repository URL. | `string` | `"https://prometheus-community.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). Generous: the Prometheus StatefulSet binds a WaitForFirstConsumer WAL PVC on first schedule. | `number` | `900` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. | `bool` | `true` | no |
| <a name="input_high_availability"></a> [high\_availability](#input\_high\_availability) | HA sizing: 2 agent replicas + hard pod anti-affinity. false = single replica (reference spoke). | `bool` | `false` | no |
| <a name="input_memory_limit"></a> [memory\_limit](#input\_memory\_limit) | Prometheus agent container memory limit. See memory\_request. | `string` | `"1Gi"` | no |
| <a name="input_memory_request"></a> [memory\_request](#input\_memory\_request) | Prometheus agent container memory request. Bump on spokes with heavier scrape cardinality (e.g. crossplane core+provider PodMonitors enabled — #1422/#1423 OOM-killed the default 512Mi/1Gi on preprod). | `string` | `"512Mi"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy the agent into. Created here (NOT by the chart) with PSA `privileged` (node-exporter needs host access) + a default-deny-ingress NetworkPolicy. | `string` | `"observability"` | no |
| <a name="input_per_team_write_url"></a> [per\_team\_write\_url](#input\_per\_team\_write\_url) | P13 per-team re-tenant (#590): the cortex-tenant ingest edge endpoint, e.g. https://preprod-tenant.aws.refplat.org/push. When set, the agent ADDITIONALLY remote\_writes here with a forced namespace→route\_tenant relabel, so cortex-tenant splits the spoke's metrics into per-team tenants — WITHOUT disturbing the primary force-stamped write to remote\_write\_url (the `preprod` tenant stays intact for the ruler/canary/cost consumers). Empty = single-write (unchanged). | `string` | `""` | no |
| <a name="input_remote_write_url"></a> [remote\_write\_url](#input\_remote\_write\_url) | Hub Mimir spoke-ingest endpoint, e.g. https://preprod-mimir.aws.refplat.org/api/v1/push. The hub Gateway force-sets X-Scope-OrgID per-hostname, so the agent deliberately sends NO tenant header (it would be overwritten). Empty disables remote\_write (agent buffers locally only). | `string` | `""` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | StorageClass for the agent's remote-write WAL PVC (buffers samples across pod restarts during a hub outage). Empty string (default) = ephemeral emptyDir WAL — portable across clusters with no StorageClass dependency, which is the right default for a lightweight spoke. Set to a class that EXISTS on the spoke cluster (e.g. gp2/gp3) for a durable WAL. | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags sanitized into K8s labels on the namespace. | `map(string)` | `{}` | no |
| <a name="input_wal_size"></a> [wal\_size](#input\_wal\_size) | Size of the agent's WAL PVC (only used when storage\_class is set). | `string` | `"5Gi"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cluster_label"></a> [cluster\_label](#output\_cluster\_label) | The `cluster` external label this spoke stamps on every series (the hub queries by it). |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace the spoke agent runs in. |
| <a name="output_remote_write_url"></a> [remote\_write\_url](#output\_remote\_write\_url) | Hub Mimir endpoint the agent ships to (empty = remote\_write disabled). |
<!-- END_TF_DOCS -->