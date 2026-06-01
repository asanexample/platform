# Observability — Current State (As-Built)

What is **actually deployed today**, and the architecture behind it. This is the operator's source of truth;
the full 14-phase roadmap (and the design rationale for phases not yet shipped) lives in
[`../plans/102-observability-stack.md`](../plans/102-observability-stack.md).

- **Use it** (access Grafana, dashboards, queries): [`../runbooks/observability-access.md`](../runbooks/observability-access.md)
- **Fix it** (troubleshooting + gotchas): [`../runbooks/observability-troubleshooting.md`](../runbooks/observability-troubleshooting.md)
- **Modules**: [`observability`](../../infra/modules/observability/README.md) · [`observability-mimir`](../../infra/modules/observability-mimir/README.md)

---

## What's live today

On the **platform** cluster, in the **`observability`** namespace:

| Component | What | Version | Notes |
|-----------|------|---------|-------|
| **kube-prometheus-stack** | Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics + prometheus-operator | chart `86.1.0` | P1 hub |
| **Grafana Mimir** | Durable, multi-tenant, S3-backed metrics store | chart `mimir-distributed 6.0.6` (app 3.0.4) | P2 — classic arch, single-replica |
| **SNS alerting** | `platform-alerts` topic → email (SSE-KMS encrypted) | — | Alertmanager `critical` route |
| **gp3 StorageClass** | cluster-default EBS storage (EBS CSI) | — | in the `eks-addons` unit |

**Not yet deployed:** Loki/Tempo (logs/traces, P3), curated per-component alert rules (P4), cloud-resource
metrics (P5), preprod spoke onboarding (P10), Grafana SSO (the P1 fast-follow — admin login for now). See
the plan for the full roadmap.

---

## Architecture

### Hub-and-spoke (single hub today)

The design is **hub-and-spoke**: one central hub (the **platform** cluster) runs Grafana + the durable
stores; spoke clusters (preprod, prod) will run collectors that `remote_write` to the hub over Tailscale/TGW.
**Today only the hub exists**, and it monitors itself — the platform cluster's own Prometheus scrapes the
platform cluster and ships to the platform-hosted Mimir. Adding preprod as a spoke is **P10**.

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

### Alerting

Bundled Prometheus mixin rules are on; **EKS-inaccurate groups are disabled** (`kubeScheduler`,
`kubeControllerManager`, `kubeEtcd`, `kubeProxy`) — the managed control plane is unscrapeable and Cilium
replaces kube-proxy, so those would be perpetual false "target down" alerts. Routing today is **minimal**:
`severity=critical` → SNS → email; the always-on `Watchdog` → null (external heartbeat is P4); everything
else → null. The SNS topic is **SSE-KMS encrypted**; the Alertmanager ServiceAccount publishes via
**IRSA + sigv4** (with `kms:GenerateDataKey*` for the encrypted topic). Curated per-component alert rules are
**P4**.

### Storage model

| Data | Where | Durability |
|------|-------|-----------|
| Prometheus TSDB (15d local) | gp3 PVC (20Gi) | survives pod restart; rebuildable from scrape |
| Alertmanager state | gp3 PVC (5Gi) | — |
| Mimir ingester WAL / store-gateway / compactor scratch | gp3 PVCs (10/10/20Gi) | local working set |
| **Mimir blocks (durable history)** | **S3** (AES256, versioned, lifecycle-pruned) | the long-term store |

gp3 is the cluster-**default** StorageClass (encrypted, expandable, WaitForFirstConsumer), created in the
`eks-addons` unit.

---

## Where it's defined (code map)

| Concern | Path |
|---------|------|
| P1 hub module | `infra/modules/observability/` |
| P2 Mimir module | `infra/modules/observability-mimir/` |
| SNS topic | `infra/modules/aws/sns-notifications/` |
| gp3 StorageClass | `infra/modules/aws/eks-addons/` (`create_default_storageclass`) |
| Live units (platform) | `infra/live/aws/platform/us-east-1/platform/{observability,mimir,sns-notifications,eks-addons,gateway-config}/` |
| Dashboards (as code) | `infra/modules/observability/dashboards/*.json` |
| Versions | `infra/live/aws/_versions.hcl` (`helm_versions.kube_prometheus_stack`, `helm_versions.mimir`) |

---

## Status notes

- **P2 Step 3** (Prometheus `remote_write` → Mimir + Prometheus/Alertmanager on gp3 PVCs + Mimir as the
  default datasource) is **applied and live on the cluster**; its code is finalizing in **PR #147** (a helm
  release-bookkeeping reconcile + a known prometheus-operator webhook-latency gotcha — see the
  [troubleshooting runbook](../runbooks/observability-troubleshooting.md)).
- **Single-replica everywhere** (`high_availability = false`) — appropriate for a reference cluster. Each
  module has an `high_availability` toggle that scales to multi-replica/RF3 when a cluster has the capacity.
