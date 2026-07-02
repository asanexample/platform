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

## policy-reporter

Namespace `observability` (P12, #93). Watches Kyverno's `PolicyReport`/`ClusterPolicyReport` CRs and
exposes them as `policy_report_result`/`cluster_policy_report_result` — both **gauges** (current report
state, re-emitted each processing cycle), so these are level checks, not `increase()`. Enforce-mode
Kyverno blocks bad resources at admission, so a fail/error surfacing here means either an Audit-mode
policy caught something or a background scan found drift — compliance evidence (ADR-013/037).

- **PolicyReporterDown** — the watcher itself is down; violation metrics and dashboards go stale. Check
  the `policy-reporter` pod/logs in `observability`.
- **PolicyReportNewViolation** / **ClusterPolicyReportNewViolation** — a fail/error PolicyReport result
  has persisted for 15m. `kubectl get policyreport -A` / `kubectl get clusterpolicyreport` for the
  underlying object (`{{ $labels.policy }}` / `{{ $labels.exported_namespace }}`); the Grafana **Policy
  Reporter** dashboard folder (Overview / PolicyReport details / ClusterPolicyReport details) has the
  full breakdown by tenant/policy/severity/source.

## true-cost-exporter

Namespace `observability`, platform hub only (#668). A small long-running exporter that queries the
mgmt-account CUR via Athena directly (cross-account AssumeRole → the `cost_reader` role, no static keys)
and serves the results as Prometheus metrics — OpenCost's own `cloudCost` pipeline is wired for its own
REST API but is **not** Prometheus-scrapeable, so this is the actual Grafana-visible true-cost path.
Refreshes every 6h (CUR itself has ~24h lag); metrics: `platform_true_cost_monthly_usd{breakdown="team|service|account",label=...}`,
`platform_true_cost_monthly_usd_total`, `platform_true_cost_compute_monthly_usd_total` (EC2-only, for
reconciling against OpenCost's in-cluster node-price estimate), `platform_true_cost_exporter_last_success_timestamp_seconds`.

- **TrueCostExporterDown** — the exporter pod itself is down. `kubectl get pods -n observability -l app=true-cost-exporter`.
- **TrueCostExporterStale** — last successful Athena refresh was over 9h ago (missed a cycle). Check
  `kubectl logs -n observability -l app=true-cost-exporter` — the two likely causes are the cross-account
  AssumeRole failing (mgmt `cost_reader` trust policy, or this side's IAM role/Pod-Identity association)
  or the Athena query itself failing (Glue table/workgroup name drift — the table name is
  crawler-discovered, not Terraform-managed, and could change if the crawler re-classifies the data).

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

## External Secrets

Namespace `external-secrets`. The Secrets-Manager → Kubernetes sync path that most workloads depend on.

- **ExternalSecretNotReady** — an `ExternalSecret` has been `Ready=False` for 15m; the synced `Secret` is
  stale. `kubectl get externalsecret -A`, then `kubectl describe externalsecret <ns>/<name>` for the
  `SecretSyncError` reason (missing SM key, IAM/Pod-Identity perms, store unreachable).
- **ClusterSecretStoreNotReady** — the `ClusterSecretStore` is `Ready=False`; the AWS provider can't auth
  or reach Secrets Manager. Check the store's status and the ESO controller's AWS credentials
  (Pod Identity / IRSA).

## Cilium

Namespace `kube-system`. The CNI / network plane — start with `cilium status` and
`docs/runbooks` Cilium debug notes (begin with `cilium monitor --type drop`).

- **CiliumAgentDown** (critical) — an agent (`{{ $labels.pod }}`) is unreachable; pods on that node lose
  networking + policy enforcement. Check the agent pod/logs on that node; eBPF datapath usually survives
  an agent restart, so a brief blip is expected during rollouts.
- **CiliumOperatorDown** (critical) — no operator is up; IPAM, identity GC, and CRD reconciliation stall.
- **CiliumUnreachableNodes** / **CiliumUnreachableHealthEndpoints** — an agent can't reach peer nodes /
  health endpoints (node-to-node or pod-to-pod connectivity degradation). Check the cilium-health status
  and the underlying VPC/security-group/route path.
- **HubbleDown** — flow observability is degraded; networking itself is unaffected. Check the Hubble
  metrics endpoint on the agent.
- **CiliumHighDropRate** — sustained non-policy packet drops (>10/s for 15m; policy-denied drops are
  excluded as expected). Start with `cilium monitor --type drop` to see drop reasons/identities, then chase
  the datapath/connectivity cause. Threshold is tunable in `curated.yaml` if it's noisy on a busier cluster.

## Cloud resources

AWS-resource metrics via **YACE** (the `cloudwatch-exporter` Deployment in `observability`; CloudWatch →
Prometheus, the P5b slice of epic 102). Metric names are `aws_<namespace>_<metric>_<stat>`. Broad ad-hoc
coverage is also available query-time via the Grafana **CloudWatch datasource** (P5a). At-a-glance state for
all three resources is on the **AWS Cloud Resources** dashboard (Platform folder); scope per ADR-079.

- **CloudNLBUnhealthyHosts** — an NLB target group (`{{ $labels.dimension_TargetGroup }}`) has unhealthy
  hosts for 15m; the gateway/LB backend is degraded. Check target-group health in the EC2 console and the
  backing Cilium gateway pods / nodes (these target groups are `k8s-default-ciliumga-*`).
- **CloudNATGatewayPortAllocationErrors** — a NAT gateway can't allocate SNAT source ports (port
  exhaustion); outbound VPC connections are being dropped. Usually too many concurrent connections to a
  single destination IP:port — spread destinations or add NAT gateways.
- **CloudTransitGatewayBlackholeDrops** — a Transit Gateway is dropping packets to a blackhole route for
  15m; cross-account traffic (platform hub ↔ preprod spoke) is hitting a missing/misconfigured route. Check
  the TGW route tables and VPC attachments (the `transit-gateway` units).

## Cost budget

Cost guardrails (ADR-091). Evaluated by the **Mimir ruler** in the env-API spoke tenant (where both the spend —
OpenCost `container_*_allocation × node_*_hourly_cost` — and the budget — `team_budget_monthly_usd{team}`, from
each `Team`'s `spec.envelope.budget.monthlyUSD` via kube-state-metrics CustomResourceState — are present). The
value is projected month-end compute spend (current allocation × 730h) as a % of the team's budget. The `team`
label routes via owner-routing (ADR-084): **critical** reaches the team's channel through the triage agent.

- **TeamCostBudgetProjectedOverrun** (warning, ≥ 80%) — team `{{ $labels.team }}` is on track to use ≥ 80% of
  its monthly cost budget. Heads-up: review what's deployed on the **Cost** dashboard (by-team / by-environment)
  before it overruns; park or scale down idle environments.
- **TeamCostBudgetOverrun** (critical, ≥ 100%) — projected to **exceed** the budget this month. Cut spend
  (scale down, park idle environments) or raise `envelope.budget.monthlyUSD` on the `Team` (a governance change).
  Note projection is naive (constant run rate); a short-lived spike clears on its own once allocation drops.

## Notification channels & secret rotation

How alerts leave the cluster, and the recurring operational tasks. Routing (set in the `observability`
module's Alertmanager config):

| severity | destinations |
|----------|-------------|
| `critical` | SNS (`platform-alerts` → email) + Slack (`#platform-alerts`) + PagerDuty (page) |
| `warning` | Slack |
| `info` / `Watchdog` / else | dashboard-only |

A `critical` inhibits a matching `warning` (same `namespace`+`alertname`) so one incident doesn't
double-notify. SNS auth is EKS Pod Identity (ADR-047) + sigv4. The **Slack webhook** and **PagerDuty routing key** are pulled from
Secrets Manager by **External Secrets**, mounted into Alertmanager (`alertmanagerSpec.secrets`), and read via
`api_url_file` / `routing_key_file` — so the secret values never enter Terraform state or helm values.

### ⚠️ Secrets must live under the `platform/` prefix

ESO's IRSA is scoped to `secret:platform/*` (the `external-secrets` unit sets `secret_path_prefix=platform`).
**Any Secrets-Manager secret ESO syncs must be named `platform/…`** or the ExternalSecret fails with
`AccessDenied` and the Alertmanager pod gets stuck mounting the missing K8s secret. Current secrets:

- Slack webhook → `platform/observability/slack-webhook` (JSON property `url`)
- PagerDuty routing key → `platform/observability/pagerduty-routing-key` (JSON property `routingKey`)

### Rotate / set a webhook or key

```bash
# Slack: api.slack.com/apps → your app → Incoming Webhooks → (re)generate the URL, then:
AWS_PROFILE=platform aws secretsmanager put-secret-value \
  --secret-id platform/observability/slack-webhook \
  --secret-string '{"url":"<new-webhook-url>"}' --region us-east-1

# PagerDuty: Service → Events API v2 integration → copy the integration key, then:
AWS_PROFILE=platform aws secretsmanager put-secret-value \
  --secret-id platform/observability/pagerduty-routing-key \
  --secret-string '{"routingKey":"<new-key>"}' --region us-east-1
```

ESO re-syncs within `refreshInterval` (1h); to apply immediately, `kubectl -n observability annotate
externalsecret <name> force-sync=$(date +%s) --overwrite` (or delete the ESO pod). No Terraform apply needed
for a rotation — only the SM value changes.

### Onboard a new channel / service

Add the secret under `platform/…`, then add an Alertmanager receiver in the `observability` module
(`slack_configs` / `pagerduty_configs` with `*_file`) + mount it via `alertmanagerSpec.secrets`, and route a
severity to it. Mirror the existing Slack/PagerDuty wiring in `infra/modules/observability/main.tf`.

### Test the path end-to-end

Port-forward Alertmanager and post a synthetic alert (severity picks the channel; `endsAt` auto-resolves):

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 &
start=$(date -u +%Y-%m-%dT%H:%M:%SZ); end=$(date -u -d '+10 minutes' +%Y-%m-%dT%H:%M:%SZ)
curl -s -X POST http://localhost:9093/api/v2/alerts -H 'Content-Type: application/json' \
  -d "[{\"labels\":{\"alertname\":\"NotifyTest\",\"severity\":\"critical\",\"namespace\":\"observability\"},
       \"annotations\":{\"description\":\"test\"},\"startsAt\":\"$start\",\"endsAt\":\"$end\"}]"
```

`severity=warning` → Slack only; `severity=critical` → SNS + Slack + PagerDuty (page). Alertmanager logs
**only failed** notifications — silence after the POST means it sent. Confirm receipt in the channel.
