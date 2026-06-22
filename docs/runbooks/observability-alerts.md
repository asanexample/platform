# Observability alert runbooks

First-response notes for the curated platform alerts in
`infra/modules/observability/alerts/curated.yaml` (observability epic 102, phase P4). Each alert's
`runbook_url` points at the matching section below. Severity routes via the Alertmanager tree
(`critical` + `warning` → SNS); a `critical` inhibits a matching `warning`.

General triage: open **Grafana → Dashboards** for the component, check **Explore → Loki**
(`{namespace="<ns>"}`) for logs around the firing time, and `kubectl -n <ns> get pods` /
`kubectl -n <ns> describe` for the workload.

## cert-manager

Namespace `cert-manager`. Guards Gateway TLS + Let's Encrypt issuance.

- **CertManagerDown** (critical) — the controller is unreachable; issuance/renewal is stalled. Check
  `kubectl -n cert-manager get pods` and the controller logs.
- **CertManagerCertExpiringCritical** (<7d) / **CertManagerCertExpiringSoon** (<21d) — a certificate is
  near expiry and hasn't renewed. `kubectl get certificate -A`, then
  `kubectl describe certificate <ns>/<name>` and the related `CertificateRequest` / `Order` for the
  blocking reason (ACME challenge, DNS-01, rate limit).
- **CertManagerCertNotReady** — the `Certificate` has been not-Ready for 1h. Same drill as expiry.
- **CertManagerSyncErrors** — the controller is logging sync errors; inspect controller logs.

## kyverno

Namespace `kyverno`. Guards the admission path (policy enforcement).

- **KyvernoAdmissionControllerDown** (critical) — the admission webhook backend is down; admission may
  fail or block deploys cluster-wide. Check the kyverno admission-controller pods/logs; if admission is
  wedged, the break-glass path is `docs/runbooks/kyverno-break-glass.md`.
- **KyvernoReportsControllerDown** / **KyvernoBackgroundControllerDown** — reports go stale /
  generate-mutate-existing stop reconciling. Check the respective controller pods.
- **KyvernoPolicyExecutionErrors** — a policy is erroring on evaluation (not just failing). Inspect the
  policy (`{{ $labels.policy_name }}`) and the controller logs.
- **KyvernoCircuitBreakerTripping** — the controller is shedding load; check resource pressure / request
  volume.

## argocd

Namespace `argocd`. GitOps reconciliation.

- **ArgoCDComponentDown** (critical) — an ArgoCD component (`{{ $labels.job }}`: app-controller /
  repo-server / server / applicationset) is unreachable for 10m. Check its pods/logs.
- **ArgoCDAppDegraded** — an application has been `Degraded` for 15m; open the app in the ArgoCD UI and
  inspect the failing resource's events.
- **ArgoCDAppOutOfSync** — an app has drifted `OutOfSync` for 15m (manual change or a failing auto-sync).
- **ArgoCDRepoServerGitErrors** — repo-server can't `git ls-remote` (`{{ $labels.repo }}`); a repo
  connectivity or credentials problem.

## Loki & Tempo stores

Namespace `observability`. The log (Loki) and trace (Tempo) stores monitoring themselves. Both write to
S3 via Pod Identity — flush failures usually mean an S3/IAM/SCP problem (see the SSE requirement in the
module READMEs).

- **LokiDown** / **TempoComponentDown** (critical) — the store (or a Tempo component `{{ $labels.job }}`)
  is unreachable; log/trace ingestion or queries are impaired. Check `kubectl -n observability get pods`
  and the pod logs.
- **LokiRequestErrors** — >5% of Loki requests are 5xx; check Loki logs and S3 reachability.
- **LokiChunkFlushFailures** / **TempoIngesterFlushFailures** — ingesters can't flush chunks/traces to
  S3 (risk of data loss / WAL backpressure). Check the pod logs for `AccessDenied` (the `enforce-encryption`
  SCP needs client-side SSE) or other S3 errors.
- **TempoBackendFlushFailures** — Tempo's backend scheduler is failing compaction flushes; same S3 triage.
- **LokiPanics** — Loki logged panics; capture logs and check for a bad query/config.
