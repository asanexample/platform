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
