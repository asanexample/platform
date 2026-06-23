# observability-blackbox

**Synthetics** (#102 P9b): **HTTP/TLS probes** of the platform's HTTPRoute endpoints via the Prometheus
**blackbox-exporter**. It exercises the real **Cilium Gateway + TLS** path (not the app's own metrics), so it
catches gateway-routing / cert breakage the app can't see.

> **Gateway-direct (not via the NLB).** The platform endpoints are internal (Tailscale-only NLB), and a pod
> can't reliably reach an *internal* NLB that load-balances back into its own cluster (NLB hairpin — probes
> flap ~40–75%). So the exporter pod gets a **`hostAlias`** mapping each probe hostname → the Cilium Gateway
> Envoy **ClusterIP**: probes keep the real `https://<host>` URL (TLS SNI + Host verify against the real cert)
> but hit Envoy directly. This reliably tests Gateway routing + TLS + the app; it does **not** test the
> DNS/NLB layer (that's the hairpin layer — true external probing of it needs a prober *outside* the cluster).

## What it deploys

- **blackbox-exporter** (`prometheus-community/prometheus-blackbox-exporter`) with one module, `http_platform`:
  GET, TLS verified (real Let's Encrypt cert — catches expiry/chain breaks), treating redirect-to-login / auth
  (3xx/401/403) as **up** (the gateway is healthy even if the app 302s to SSO).
- A **Probe CR** (`monitoring.coreos.com/v1`) over `probe_targets`. The hub Prometheus discovers it
  (`probeSelectorNilUsesHelmValues=false`) and scrapes the exporter per target.

## Metrics produced

`probe_success`, `probe_http_status_code`, `probe_duration_seconds`, `probe_ssl_earliest_cert_expiry`
(+ phases), labelled `instance=<url>` — remote-written to Mimir. Build an **external-availability SLO** on
`probe_success` (observability-slo) and a **cert-expiry alert** on `probe_ssl_earliest_cert_expiry`.

> k6 scripted checks are the other half of P9b synthetics — a follow-up.
