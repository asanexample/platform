# observability-slo

**SLOs & error budgets** (#102 P9) via **Sloth**. Define SLOs abstractly (`{ objective, window, error/total
query }`); Sloth's controller generates the **SLI recording rules** + **multi-window burn-rate alert rules**
as `PrometheusRule` objects. The hub Prometheus discovers them (`ruleSelectorNilUsesHelmValues=false`),
evaluates them, and remote-writes the SLO metrics to Mimir; burn-rate **alerts route via the P4 Alertmanager**
by severity (`pageAlert`=critical → page, `ticketAlert`=warning → Slack).

## What it deploys

- **Sloth controller** (`slok/sloth`) — watches `PrometheusServiceLevel` CRs (the chart bundles the CRD).
- **SLO definitions** — `PrometheusServiceLevel` CRs rendered from the `slos` input, via a small **local
  chart** (so the CRs don't need the CRD at plan time, unlike `kubernetes_manifest`).
- **SLO dashboard** — grafana.com **14643** ("High level Sloth SLOs"), provisioned as code (Grafana sidecar),
  datasource picker scoped to the Mimir datasources.

## Engine seam

`slo_engine` defaults to `sloth` (the only implementation). It's the seam for a future `pyrra` / Grafana SLO
swap (ADR-043 OSS-default / commercial opt-in) — the abstract `slos` definitions stay the same.

## Usage

```hcl
module "slo" {
  source    = "../../modules/observability-slo"
  namespace = "observability"
  slos = [{
    name        = "kubernetes-apiserver"
    service     = "kubernetes-apiserver"
    slo_name    = "requests-availability"
    description = "API server request availability (non-5xx)."
    objective   = 99.9
    error_query = "sum(rate(apiserver_request_total{code=~\"5..\"}[{{.window}}]))"
    total_query = "sum(rate(apiserver_request_total[{{.window}}]))"
    alert_name  = "K8sApiserverAvailability"
  }]
}
```

> Queries use Sloth's `{{.window}}` placeholder — Sloth fills it per burn-rate window. (Helm does not
> re-evaluate value content, so the `{{ }}` passes through to the CR untouched.)
