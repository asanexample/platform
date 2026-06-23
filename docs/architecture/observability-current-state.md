# Observability — Current State (As-Built)

What is **actually deployed today**, and the architecture behind it. This is the operator's source of truth;
the full 14-phase roadmap (and the design rationale for phases not yet shipped) lives in
[`../plans/102-observability-stack.md`](../plans/102-observability-stack.md).

- **Use it** (access Grafana, dashboards, queries): [`../runbooks/observability-access.md`](../runbooks/observability-access.md)
- **Fix it** (troubleshooting + gotchas): [`../runbooks/observability-troubleshooting.md`](../runbooks/observability-troubleshooting.md)
- **Modules**: [`observability`](../../infra/modules/observability/README.md) · [`observability-mimir`](../../infra/modules/observability-mimir/README.md) · [`observability-loki`](../../infra/modules/observability-loki/README.md) · [`observability-tempo`](../../infra/modules/observability-tempo/README.md) · [`observability-alloy`](../../infra/modules/observability-alloy/README.md) · [`observability-otel-collector`](../../infra/modules/observability-otel-collector/README.md) · [`observability-events`](../../infra/modules/observability-events/README.md)

---

## What's live today

On the **platform** cluster, in the **`observability`** namespace:

| Component | What | Version | Notes |
|-----------|------|---------|-------|
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics + prometheus-operator | chart `86.1.0` | P1 hub — always on |
| **Grafana Loki** | Logs store (single-binary), S3-backed, **Pod Identity** | chart `loki 7.0.0` | P3a — `enable_loki` |
| **Grafana Alloy** | Log-collector DaemonSet (node-local pod logs → Loki) | chart `alloy 1.10.0` | P3a — `enable_log_pipeline` |
| **K8s events → Loki** | Alloy singleton watching cluster Events → Loki | chart `alloy 1.10.0` | P3b — `enable_log_pipeline` |
| **Grafana Tempo** | Traces store (`tempo-distributed`, minimized), S3-backed, **Pod Identity** | chart `tempo-distributed 2.25.5` (app 2.10.7, **grafana-community**) | P3b — `enable_tempo` |
| **OpenTelemetry Collector** | Trace gateway (OTLP in → Tempo) | chart `opentelemetry-collector 0.158.2` | P3b — `enable_trace_pipeline` |
| **Curated alerts** | 28 `PrometheusRule`s across 7 components (+ bundled mixins) | — | P4 |
| **Notifications** | `warning`→Slack · `critical`→SNS+Slack+PagerDuty · inhibition | — | P4; secrets via ESO |
| **gp3 StorageClass** | cluster-default EBS storage (EBS CSI) | — | in the `eks-addons` unit |
| **Grafana Mimir** | Durable, multi-tenant, S3-backed metrics store | chart `mimir-distributed 6.0.6` | P2 — **ON** on the platform hub (`enable_mimir=true`); Prometheus `remote_write`s here; the hub-and-spoke store |
| **Prometheus agent (preprod spoke)** | kube-prometheus-stack agent mode (+ KSM + node-exporter) on **preprod**, `remote_write`s to the hub Mimir under tenant `preprod` | chart `kube-prometheus-stack 86.1.0` | P10 — `infra/modules/observability-prometheus-agent` |

> **cost_profile (`common.hcl`/`_base.hcl`):** `dev` (default) = single-replica + durable stores **off**. The
> platform cluster overrides `enable_mimir` / `enable_loki` / `enable_log_pipeline` / `enable_tempo` /
> `enable_trace_pipeline` **on** in its `env.hcl` (so the full LGTM bundle runs single-replica), while other
> clusters stay dev/off. `cost_profile=prod` flips the bundle to HA (RF3, multi-replica).

**Not yet deployed:** cross-cluster **logs/traces** spokes (P10 shipped metrics first), Grafana SSO (deferred
hardening — admin login for now). Full roadmap in the plan.

---

## Architecture

### Hub-and-spoke (single hub today)

The design is **hub-and-spoke**: one central hub (the **platform** cluster) runs Grafana + the durable
stores; spoke clusters run lightweight collectors that `remote_write` to the hub over the Transit Gateway.
The hub monitors itself (its own Prometheus → the hub Mimir, tenant `platform`), and **preprod** is the first
**metrics spoke** (P10): a kube-prometheus-stack agent on preprod ships to the hub Mimir under tenant
`preprod`. Logs/traces spokes are the next step.

**Cross-cluster ingest edge (Gateway-API-native, no proxy).** The hub Mimir is `ClusterIP`-only; spokes reach
it through a write-only **HTTPRoute** on the shared Cilium Gateway (`<spoke>-mimir.aws.refplat.org`,
self-routed by the `observability-mimir` module's `spoke_ingest` input). The HTTPRoute does two
security-critical jobs declaratively: a `RequestHeaderModifier` **force-sets `X-Scope-OrgID`** to the spoke's
tenant — overwriting any client value, so a spoke can't spoof another tenant (the ADR-044 guard) — and a path
match on `/api/v1/push` keeps it **write-only** (no query path is exposed cross-cluster). A
`CiliumNetworkPolicy` (`fromEntities: ["ingress"]`) admits the Gateway Envoy to the Mimir gateway past the
`observability` default-deny. **Auth = network isolation** (the internal NLB reachable only over the VPC/TGW);
mTLS is the planned P10.x hardening. The spoke sends **no** tenant header (the edge sets it) and **no**
credential. Onboarding the next spoke: [`observability-spoke-onboarding.md`](../runbooks/observability-spoke-onboarding.md).

```text
              ┌─────────────────────────  observability namespace (platform cluster)  ──────────────────────┐
  scrapes     │  Prometheus ──remote_write(X-Scope-OrgID: platform)──▶  Mimir gateway ─▶ distributor        │
  cluster ───▶│   │  (15d local, gp3 PVC)                                 │              ▶ ingester ─┐       │
  targets     │   │                                                       │              ▶ querier   │ S3   │
              │   ▼                                                  query │              ▶ q-frontend│blocks│
              │  Alertmanager ──sns_configs(sigv4/IRSA)──▶ SNS ──▶ email   │              ▶ store-gw ◀─┘bucket│
              │   │  (gp3 PVC)                                             │              ▶ compactor ─▶ S3   │
              │   ▼                                                        │                                  │
              │  Grafana ◀── Mimir datasource (default, X-Scope-OrgID: platform) ─────────┘                  │
              │   ▲   ◀── Prometheus datasource (recent/local, non-default)                                  │
              └───┼──────────────────────────────────────────────────────────────────────────────────────────┘
                  │ HTTPRoute (Cilium Gateway, internal NLB, cert-manager TLS)
            grafana.aws.refplat.org   ◀── Tailscale-only (no public exposure)
```

### Metrics path: Prometheus + Mimir (additive)

Prometheus stays the **scraper** with a short local retention (15d, on a gp3 PVC); it **`remote_write`s**
every sample to **Mimir**, which is the durable, long-range store on **S3**. Grafana's **default datasource
is Mimir** (full history); the Prometheus datasource remains selectable for recent/local queries. This is
additive — no migration, and Prometheus can be lost/rebuilt without losing history (it's in Mimir/S3).

Mimir runs in **classic architecture** (distributor → ingester gRPC, RF1), *not* the chart's default Kafka
ingest-storage — lighter for a reference cluster. Components: gateway (nginx), distributor, ingester,
querier, query-frontend, **query-scheduler** (required — the chart wires querier→scheduler), store-gateway,
compactor. Ingester/store-gateway/compactor are StatefulSets on **gp3** PVCs; durable blocks live in the
**AES256** S3 bucket reached via **IRSA** (no static keys).

> Mimir itself is **off in the dev cost_profile** today (`enable_mimir=false`); the above is the metrics
> path when Mimir is enabled (prod profile, or a future dev flip). In dev, Prometheus serves metrics
> directly (no remote-write) and is Grafana's metrics datasource.

### Logs path: Loki + Alloy (P3a)

**Grafana Alloy** runs as a DaemonSet — each agent tails *its own node's* `/var/log/pods` (a
`spec.nodeName`-filtered `discovery.kubernetes` + `loki.source.file`, so no duplicate ingestion) and writes
to **Loki** under tenant `platform`. A second Alloy **singleton Deployment** watches the Kubernetes **Events**
API (`loki.source.kubernetes_events`) and ships events to Loki too — so events sit next to logs. Loki runs
single-binary; durable chunks live on **S3 via Pod Identity** (ADR-047 — no IRSA), and it's the Grafana
**Loki** datasource. Per-team tenant derivation is P10.

### Traces path: Tempo + OpenTelemetry Collector (P3b)

Apps send **OTLP** to a deployment-mode **OpenTelemetry Collector** (`otelcol-k8s`;
`otlp → memory_limiter → batch → otlp/tempo`), which forwards to **Tempo**'s distributor. Tempo uses the
`tempo-distributed` chart **minimized for dev** (each component 1 replica, RF1, caches/gateway/metrics-gen
off; `prod` scales it via `high_availability`); durable blocks on **S3 via Pod Identity**. The Grafana
**Tempo** datasource links **traces↔logs** (`tracesToLogsV2` → Loki; Loki's `trace_id` derivedField → Tempo).

### Multi-cluster view — federated datasource (#626)

Each cluster is a separate Mimir tenant (`platform`, `preprod`), so by default one datasource = one cluster
(strong read-isolation). For a **platform-admin overview across clusters**, Mimir **tenant federation** is
enabled (`tenant_federation.enabled`) and a **`Mimir (all clusters)`** Grafana datasource queries every tenant
at once (`X-Scope-OrgID: platform|preprod`). Write-isolation is unaffected — the Gateway edge still
force-stamps a single tenant per spoke. The **Platform Health** dashboard defaults to this datasource and has
a `cluster` multi-select, so panels break out per cluster. Per-team scoping of the federated lane is **P13**
(#590); cross-cluster **logs/traces** federation follows their spokes (#627/#628). Umbrella: #629.

> **Known wrinkle (data layer only):** the Loki/Mimir charts stamp their own `cluster` label on self-metrics
> (`cluster=loki`/`cluster=mimir`), polluting the raw `cluster` dimension. The dashboard's `cluster` dropdown
> sidesteps this by deriving values from `kube_node_info` (KSM — real clusters only), so the UI is clean;
> relabeling the self-metrics so `externalLabels.cluster` is authoritative is tracked in #630.

### Multi-tenancy & the security boundary (read this)

Mimir runs with `multitenancy_enabled: true`. The tenant is the **`X-Scope-OrgID`** header; the hub's own
metrics use tenant **`platform`**. When spokes onboard (P10), each writes under its own tenant.

> **`X-Scope-OrgID` is a trust header, not authentication.** Mimir does not authenticate it — anything that
> can reach the Mimir endpoint and set the header can read/write any tenant (the nginx gateway even fills in
> a default tenant when the header is absent). **The actual isolation boundary is the NetworkPolicy:** the
> `observability` namespace has a **default-deny ingress** + an allow only for intra-namespace traffic, so
> `team-*` (and every other) namespace **cannot reach Mimir at all**. Mimir is **never** exposed through the
> Cilium Gateway (ClusterIP only — unlike Grafana). Cross-cluster ingest from spokes (P10) must be
> authenticated and have the header overwritten at the hub edge.

### Network & exposure

- **Grafana** is the only externally-reachable component: an HTTPRoute on the Cilium Gateway (internal NLB,
  `internal` scheme) → **Tailscale-only**, TLS via cert-manager (Let's Encrypt DNS-01). Hardened: anonymous
  off, no sign-up/org-create, viewers can't edit, secure cookies, unsigned plugins disabled.
  - **Gotcha:** the Cilium gateway's Envoy connects with the reserved Cilium `ingress` identity (8), which a
    standard k8s NetworkPolicy `from:` can't match — Grafana ingress is allowed via a **CiliumNetworkPolicy**
    `fromEntities: ["ingress"]`. (CLAUDE.md "Cilium Gateway API".)
- **Namespace PSA** = `privileged` (node-exporter needs hostNetwork); the namespace is created by Terraform
  (not the chart) so the label is set, and intentionally carries **no tenant label** (so Kyverno tenant
  policies don't apply; `observability` is also in the policy `exclude_namespaces`).

### Alerting (P4)

Bundled Prometheus mixin rules are on; **EKS-inaccurate groups are disabled** (`kubeScheduler`,
`kubeControllerManager`, `kubeEtcd`, `kubeProxy`) — the managed control plane is unscrapeable and Cilium
replaces kube-proxy. On top of the mixins, **28 curated `PrometheusRule`s** cover 7 components —
cert-manager, kyverno, ArgoCD, Loki, Tempo, External Secrets, Cilium (+ Hubble) — each grounded in
live-verified metrics with a `runbook_url` → [`observability-alerts.md`](../runbooks/observability-alerts.md).
Component metrics are scraped via the chart's `additionalServiceMonitors`/`additionalPodMonitors` (the
Cilium/ESO chart ServiceMonitors are off or capability-gated, so we define them on the observability side —
see Gotchas). Rules live in `infra/modules/observability/alerts/curated.yaml`.

**Routing** — severity tree with inhibition (a `critical` suppresses a matching `warning`):

| severity | destinations |
|----------|-------------|
| `critical` | **SNS** (email) + **Slack** (`#platform-alerts`) + **PagerDuty** (page; Events API v2) |
| `warning` | **Slack** |
| `info` / `Watchdog` / else | dashboard-only (`null`) |

SNS publishes via **IRSA + sigv4** (SSE-KMS topic). The **Slack webhook** and **PagerDuty routing key** are
synced from Secrets Manager by **External Secrets** and read by Alertmanager via `api_url_file` /
`routing_key_file` — the secrets never enter Terraform state or helm values (see the
[notification-channels runbook](../runbooks/observability-alerts.md#notification-channels--secret-rotation)).
**Deploy/change annotations** (a Prometheus query on `kube_deployment_metadata_generation` changes) overlay
the platform dashboards so a metric blip can be tied to a rollout.

### Storage model

| Data | Where | Durability |
|------|-------|-----------|
| Prometheus TSDB (15d local) | gp3 PVC (20Gi) | survives pod restart; rebuildable from scrape |
| Alertmanager state | gp3 PVC (5Gi) | — |
| Mimir ingester WAL / store-gateway / compactor scratch | gp3 PVCs (10/10/20Gi) | local working set (Mimir off in dev) |
| **Mimir blocks (durable history)** | **S3** (AES256, versioned, lifecycle-pruned) | the long-term metrics store |
| **Loki chunks (logs)** | **S3** (AES256, SSE-S3 request header, Pod Identity) | durable log store |
| **Tempo blocks (traces)** | **S3** (AES256, SSE-S3 request header, Pod Identity) | durable trace store; `block_retention` 72h |
| Loki / Tempo-ingester WAL | gp3 PVCs (~5Gi) | local working set |

gp3 is the cluster-**default** StorageClass (encrypted, expandable, WaitForFirstConsumer), created in the
`eks-addons` unit.

### Decisions & gotchas (durable)

- **New add-ons use EKS Pod Identity, not IRSA** (ADR-047). Loki/Tempo trust `pods.eks.amazonaws.com` (no
  `eks.amazonaws.com/role-arn` annotation). The existing add-on layer (kube-prometheus-stack / Mimir /
  Alertmanager, argocd, cert-manager, external-dns, crossplane) is still on IRSA and migrates as a batch in
  **#594**.
- **The org `enforce-encryption` SCP denies `s3:PutObject` without the `x-amz-server-side-encryption`
  header** — bucket default encryption alone doesn't add it. **Every S3 client must send SSE explicitly**
  (Loki `storage.s3.sse=SSE-S3`, Tempo `storage.trace.s3.sse=SSE-S3`). Loki was the first store to actually
  write, so it surfaced this; Mimir needs the same when enabled.
- **External Secrets IRSA is scoped to `secret:platform/*`** (the platform `external-secrets` unit sets
  `secret_path_prefix=platform`). **Every ES-synced Secrets Manager secret must be named `platform/…`** or
  ESO gets `AccessDenied` (the Slack webhook + PD routing-key secrets live under that prefix).
- **Chart ServiceMonitors are unreliable, so scraping is defined on the observability side.** Cilium's chart
  ServiceMonitors are intentionally off (Cilium installs before the Prometheus-operator CRDs in the DAG);
  the ESO chart's ServiceMonitor is capability-gated and didn't render via the helm provider. Both are
  scraped via `additionalServiceMonitors` / `additionalPodMonitors` in the observability module instead.
- **Tempo's Helm charts moved to `grafana-community/helm-charts`** (Jan 2026; the `grafana/helm-charts`
  copies are `deprecated:true`), so `tempo-distributed` is pulled from the community repo. Loki/Mimir/Alloy
  charts are unaffected. (`k8s-monitoring` is a *collector* chart, not a backend deploy — not used.)
- **Manual `terragrunt apply` on platform units needs `AWS_PROFILE=management`** (per `.platctl.yaml`; a bare
  shell is the mgmt IAM user and 403s assuming `PlatformDeployer`).

---

## Where it's defined (code map)

| Concern | Path |
|---------|------|
| P1 hub module (+ alerting routing, dashboards, ES-synced Slack/PD secrets) | `infra/modules/observability/` |
| Curated alert rules | `infra/modules/observability/alerts/curated.yaml` |
| Logs — store / collector | `infra/modules/observability-loki/` · `infra/modules/observability-alloy/` |
| Events → Loki | `infra/modules/observability-events/` |
| Traces — store / collector | `infra/modules/observability-tempo/` · `infra/modules/observability-otel-collector/` |
| Metrics durable store (+ cross-cluster `spoke_ingest` edge) | `infra/modules/observability-mimir/` |
| Metrics spoke collector (preprod) | `infra/modules/observability-prometheus-agent/` · runbook `docs/runbooks/observability-spoke-onboarding.md` |
| SNS topic | `infra/modules/aws/sns-notifications/` |
| gp3 StorageClass | `infra/modules/aws/eks-addons/` (`create_default_storageclass`) |
| Live units (platform) | `infra/live/aws/platform/us-east-1/platform/{observability,loki,alloy,events,tempo,otel-collector,mimir,sns-notifications,eks-addons,gateway-config}/` |
| Live units (preprod spoke) | `infra/live/aws/preprod/us-east-1/platform/observability-spoke/` |
| Dashboards (as code) | `infra/modules/observability/dashboards/*.json` |
| cost_profile toggle | `infra/live/aws/common.hcl` + `_base.hcl`; per-cluster overrides in `…/platform/env.hcl` |
| Versions | `infra/live/aws/_versions.hcl` (`helm_versions.{kube_prometheus_stack,mimir,loki,alloy,tempo,otel_collector}`) |

---

## Status notes

- **P3 (logs + traces) and P4 (alerting + notifications) are applied and live** on the platform cluster
  (PRs #596–#612): logs queryable in Grafana (Loki + Alloy + K8s events), traces flowing (Tempo + OTel
  collector, with trace↔logs correlation), and 28 curated alerts routing to SNS / Slack / PagerDuty.
- **Metrics are Prometheus-only in dev** — Mimir is code-complete but `enable_mimir=false` (cost_profile),
  so there's no `remote_write` and Prometheus is Grafana's metrics datasource. The P2 Mimir path (merged
  PR #147) activates when Mimir is enabled (prod profile). Known wrinkle when enabling: a prometheus-operator
  webhook-latency gotcha during the helm reconcile — see the
  [troubleshooting runbook](../runbooks/observability-troubleshooting.md).
- **Sizing follows `cost_profile`** — `dev` (default) is single-replica with durable stores off; `prod`
  flips the bundle to HA/RF3. The platform cluster runs `dev` with logs + traces toggled on.
- **Grafana SSO** (OIDC) is a deferred hardening step — admin login for now. When it lands, keep a
  local-admin break-glass (OIDC-only would break programmatic/automation access).
