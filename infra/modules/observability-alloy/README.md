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
- **Log→trace correlation (ADR-100)** — the per-team `retenant` process (gated on `per_team_tenant`) also
  extracts each app's OTel `trace_id`/`span_id` out of the JSON log body via a quote-free regex and promotes
  them to **Loki structured metadata** (not new index labels — no added cardinality), so `observability-loki`'s
  derived field can link a log line straight to its trace by matching on that field (`matcherType: label`)
  instead of re-scraping the raw line at query time. Only fires for SDK-instrumented services (the fields must
  already be in the JSON body); non-request / non-SDK log lines simply carry no such metadata.
- **No phone-home** (`enableReporting=false`); chart CRDs off (`crds.create=false` — we run a plain collector).
- Gated by **`enable_log_pipeline`** (cost_profile per-knob override); points at the `observability-loki`
  `push_endpoint`.

## Key inputs

| Input | Default | Notes |
|-------|---------|-------|
| `loki_push_url` | loki-gateway push URL | wire to the `observability-loki` `push_endpoint` output |
| `tenant_id` | `platform` | X-Scope-OrgID on platform logs (the fallback tenant when `per_team_tenant` is on) |
| `per_team_tenant` | `false` | P13: re-tenant env-namespace logs per team (#590); also gates the trace_id/span_id→structured-metadata promotion (ADR-100) — both live on platform + preprod |
| `helm_chart_version` | `1.10.0` | pinned in `_versions.hcl` |

(Full input reference is auto-generated below.)

## Verify

After apply: `kubectl -n observability get ds alloy` (one pod per node Ready), then in Grafana → Explore → Loki,
query `{namespace="observability"}` — platform logs appear. Trace→logs correlation lands with Tempo (P3b).

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
| [helm_release.alloy](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_external_labels"></a> [external\_labels](#input\_external\_labels) | Static labels stamped on every log stream (Alloy loki.write external\_labels). For a spoke, set `{ cluster = "preprod" }` so the hub can isolate/break-out logs by cluster (#627), matching the metrics `externalLabels.cluster`. Empty = none. | `map(string)` | `{}` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name. | `string` | `"alloy"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | grafana/alloy chart version (pinned in \_versions.hcl; resolved latest stable at authoring). | `string` | `"1.10.0"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name (also fullnameOverride + the ServiceAccount name). | `string` | `"alloy"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm repository URL. | `string` | `"https://grafana.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm operation timeout (seconds). A DaemonSet rolls out quickly; no PVCs. | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. | `bool` | `true` | no |
| <a name="input_loki_push_url"></a> [loki\_push\_url](#input\_loki\_push\_url) | Loki push endpoint (gateway) Alloy ships logs to — e.g. the observability-loki module's push\_endpoint output. | `string` | `"http://loki-gateway.observability.svc/loki/api/v1/push"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy Alloy into. Defaults to the observability hub namespace (shares the default-deny NetworkPolicy isolation). Must already exist (created by the observability module). | `string` | `"observability"` | no |
| <a name="input_per_team_tenant"></a> [per\_team\_tenant](#input\_per\_team\_tenant) | P13 per-team log isolation (#590): derive each log stream's Loki tenant from the pod's Kyverno-injected `team` label (env-namespace pods) instead of a single static tenant; system pods fall back to `tenant_id`. This is the WRITE half — reads are enforced by the loki-tenant-proxy. For a spoke, requires the hub Loki ingest edge to pass the tenant through rather than force-stamp it (write-integrity hardened later by ingest mTLS). Off by default (unchanged single-tenant behaviour). | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags sanitized into K8s labels (Alloy creates no AWS resources). | `map(string)` | `{}` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Tenant (X-Scope-OrgID) Alloy stamps on platform logs. The fallback tenant for system pods when per\_team\_tenant is on; the sole tenant when it's off. | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Helm release name of the Alloy log-collector DaemonSet (empty when not created). |
<!-- END_TF_DOCS -->