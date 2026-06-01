# ADR-043: Self-Hosted Prometheus/Grafana Observability Stack

**Date:** 2026-05-31

**Status:** Accepted — P1 implemented + live on the platform cluster. Establishes the observability
foundation; the durable store is split into [ADR-044](044-mimir-durable-multi-tenant-metrics.md) (Mimir).
Full design + roadmap in `docs/plans/102-observability-stack.md`; as-built in
[observability-current-state](../architecture/observability-current-state.md).

## Context

The platform had no metrics, dashboards, or alerting — operators flew blind, and there was no foundation
for SLOs, capacity planning, or the multi-cluster signal the hub-and-spoke topology will need. We need a
metrics + dashboards + alerting layer for the platform cluster (and, later, preprod/prod spokes).

This is a **reference Internal Developer Platform** built **OSS-default** (the same stance as the rest of
the stack): capability-not-vendor, portable, cost-conscious, with dashboards and alerts expressed **as
code**. The observability layer should fit that, expose a single pane of glass, and be the base the durable
store (Mimir, ADR-044) and later logs/traces (Loki/Tempo) plug into.

### Alternatives considered

**1. Self-hosted `kube-prometheus-stack` (chosen).** The community Helm bundle: Prometheus +
prometheus-operator + Grafana + Alertmanager + node-exporter + kube-state-metrics, with curated mixin
dashboards/alerts. OSS, portable, dashboards-as-code via the Grafana sidecar, Grafana fronts Mimir/Loki/Tempo
later. Cost is compute we already run; the trade is that **we operate it**.

**2. AWS managed — Amazon Managed Prometheus (AMP) + Managed Grafana (AMG) + CloudWatch (rejected).**
Less to operate, but: per-sample ingestion + per-query billing that grows with cardinality; AMG is
per-user-priced; CloudWatch Container Insights is costly at metric granularity and weaker for ad-hoc PromQL;
weaker dashboards-as-code; AWS-only (not portable for a multi-cloud-capable reference). Reasonable for a pure
AWS shop — revisit per-cluster if the ops burden outweighs the cost/portability win (the modules carry a
`metrics_backend`-style seam for exactly this).

**3. SaaS — Datadog / Grafana Cloud / New Relic (rejected).** Best operability, worst fit here: per-host /
per-series pricing is the dominant platform cost at scale, data leaves the account, and it's the opposite of
OSS-default. Not appropriate for a cost-conscious reference platform.

**4. Hand-rolled Prometheus + Grafana (without the bundle) (rejected).** Loses the operator, the curated
mixins, and the maintained packaging for no benefit.

## Decision

Run the **self-hosted `kube-prometheus-stack`** (chart 86.1.0) as the observability **hub** on the platform
cluster, in a dedicated `observability` namespace, in a **hub-and-spoke** topology (one hub today; spokes
remote-write later — `docs/plans/102-observability-stack.md`, P10).

Load-bearing choices baked in:

- **Grafana exposed Tailscale-only** (internal NLB + Cilium Gateway HTTPRoute, cert-manager TLS); hardened
  (anonymous off, no sign-up, secure cookies). Admin via an External-Secrets/Secrets-Manager credential;
  Dex→Identity Center SSO is a fast-follow ([ADR-012](012-argocd-sso-via-dex-saml.md) pattern).
- **EKS accuracy:** the `kubeScheduler`/`kubeControllerManager`/`kubeEtcd`/`kubeProxy` scrape jobs **and**
  their alert rule groups are disabled — the managed control plane is unscrapeable and Cilium replaces
  kube-proxy, so they would otherwise be empty dashboards + perpetual false "target down" alerts.
- **Alerting:** bundled mixin rules + a minimal `critical → SNS → email` route (the `sns-notifications`
  module / `platform-alerts` topic), via Alertmanager **IRSA + sigv4** ([ADR-018](018-irsa-for-pod-identity.md)).
  Curated per-component alerts are deferred (P4).
- **Dashboards as code** — JSON in the module, sidecar-provisioned ConfigMaps. A custom "Platform Health"
  overview + vendored upstream dashboards.
- **Durability + multi-tenancy are a separate decision** — Prometheus keeps only a short local retention;
  the durable, multi-tenant store is **Mimir** ([ADR-044](044-mimir-durable-multi-tenant-metrics.md)), which
  Prometheus `remote_write`s to.

`high_availability` is a per-unit toggle (Prom ×2 / AM ×3 / Grafana ×2 + PDBs), off on the reference cluster
— same pattern as the ArgoCD module.

## Consequences

### Positive

- **Full visibility + a foundation** — metrics, dashboards, alerting now exist, and Grafana is the single
  pane the durable store (ADR-044) and future logs/traces plug into.
- **OSS, portable, cost-controlled** — no per-host/per-series licensing; the cost is compute we already run;
  the stack moves across clouds.
- **Dashboards + alerts as code** — provisioned via the module + sidecar; reviewable, versioned, rebuildable.
- **Right-sized** — single-replica on the reference cluster, HA behind one toggle.

### Negative

- **We operate it** — upgrades, scaling, storage, and incident response are ours (the explicit trade vs.
  managed/SaaS). A runbook captures the operational gotchas
  ([observability-troubleshooting](../runbooks/observability-troubleshooting.md)).
- **Single-cluster + short retention by itself** — Prometheus alone is not durable, not multi-tenant, and
  doesn't span clusters; that gap is what makes ADR-044 (Mimir) necessary, not optional.
- **Storage friction on EKS** — needed a gp3 default StorageClass; the emptyDir→PVC migration triggers an
  operator-driven StatefulSet recreation that deadlocks `helm --wait` (documented in the runbook).
- **SSO is a fast-follow** — admin-password login until Dex→Identity Center lands.
- **Cost/portability win is conditional** — at large scale or a pure-AWS posture, managed (AMP/AMG) may win;
  the `metrics_backend` seam keeps that switch open.
