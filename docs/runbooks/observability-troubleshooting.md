# Runbook — Observability Troubleshooting

Diagnostics for the observability stack (Grafana, Prometheus, Alertmanager, Mimir) and the **non-obvious
gotchas** baked into how it's deployed. Architecture: [`../architecture/observability-current-state.md`](../architecture/observability-current-state.md).
Access basics (login, datasources): [`observability-access.md`](observability-access.md).

All commands assume `--context platform` and namespace `observability` unless noted.

```bash
kubectl --context platform -n observability get pods        # first look — what's not Ready?
```

---

## Grafana

### "grafana.aws.refplat.org not responding"

Work outward from the pod:

```bash
# 1. Grafana pod healthy?
kubectl -n observability get pods -l app.kubernetes.io/name=grafana
kubectl -n observability logs deploy/kube-prometheus-stack-grafana -c grafana --tail=50
# 2. Gateway Envoy + HTTPRoute accepted?
kubectl -n observability get httproute
kubectl get pods -A | grep -i cilium-gateway          # Envoy running?
# 3. Tailscale path — are you on the tailnet, are the subnet routers advertising the VPC CIDR?
tailscale status | grep -i route
```

Most "not responding" turns out to be a **transient Tailscale path** (subnet router / DNS), not the cluster
— if the Grafana pod is `200 OK` internally and the HTTPRoute is `Accepted`, it's the network path.

Internal health check (bypasses Tailscale/gateway):

```bash
kubectl -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- wget -qO- -S http://localhost:3000/api/health
```

### Grafana returns 502/timeout through the gateway but the pod is healthy → **Cilium ingress identity**

The Cilium gateway's Envoy connects with the reserved Cilium **`ingress` identity (8)**, which a *standard*
k8s NetworkPolicy `from:` **cannot** match. Grafana ingress is allowed by a **CiliumNetworkPolicy**
(`fromEntities: ["ingress"]`). If that CNP is missing/wrong, the gateway is denied even though everything
else is fine.

```bash
kubectl -n observability get ciliumnetworkpolicy
# the allow-grafana-from-gateway CNP must have ingress.fromEntities: [ingress] on port 3000
```

Background: CLAUDE.md "Cilium Gateway API" / memory `feedback_cilium_gateway_identity`. When debugging Cilium
drops, start with `cilium monitor --type drop`, not traces.

### Two "default" datasources / dashboards query the wrong store

The bundled Prometheus datasource and the Mimir datasource must not **both** be default. The module sets
`grafana.sidecar.datasources.defaultDatasourceEnabled = false` when Mimir is wired, leaving the **Mimir**
datasource (`isDefault: true`) as the sole default. If panels show only ~15d of data, they're on Prometheus —
check the datasource defaults.

---

## Prometheus → Mimir `remote_write`

### Is remote_write actually flowing?

```bash
kubectl -n observability exec sts/prometheus-kube-prometheus-stack-prometheus -c prometheus -- \
  wget -qO- http://localhost:9090/metrics | grep -E 'prometheus_remote_storage_(samples_total|samples_failed_total|samples_pending)'
```

- `samples_failed_total` climbing → writes are being rejected. Check:
  - **Mimir gateway reachable?** `wget http://mimir-gateway.observability.svc/api/v1/push` from the
    Prometheus pod (both are in `observability`, so the intra-namespace NetworkPolicy allows it).
  - **`X-Scope-OrgID` header set?** The Prometheus CR's `remoteWrite[].headers` must include
    `X-Scope-OrgID: platform`. Without it the nginx gateway buckets writes into a default tenant.
  - **Per-tenant limits hit?** Mimir distributor logs `per-user series limit` / `ingestion rate limit` →
    raise `max_global_series_per_user` / `ingestion_rate` in the `observability-mimir` module.
- `samples_pending` high + `failed` ~0 → Mimir is slow/backpressured (ingester resources), not rejecting.

The bundled `PrometheusRemoteWriteBehind` / `...Failing` alerts cover this once remote_write is on.

---

## Mimir

### A Mimir pod isn't Ready

```bash
kubectl -n observability get pods -l app.kubernetes.io/name=mimir
kubectl -n observability logs <pod> --tail=100 | grep -iE "level=error|level=warn"
```

Known patterns:

- **Querier: `failed DNS A record lookup ... mimir-query-scheduler-headless`** → the **query-scheduler is
  disabled**. It is **required** in this chart: the querier's `frontend_worker` and the query-frontend are
  wired to the scheduler and the chart has no scheduler-less mode. Keep `query_scheduler.enabled = true`.
- **Writes rejected / ingester won't accept** → with a single ingester, `replication_factor` must be **1**
  (`mimir.structuredConfig.ingester.ring.replication_factor`). RF3 with one ingester rejects writes.
- **A `mimir-kafka` pod appears** → the chart defaulted to the **Kafka ingest-storage** architecture. We run
  **classic**: `kafka.enabled=false` + `ingest_storage.enabled=false` + `ingester.push_grpc_method_enabled=true`.
  (Delete the orphaned `kafka-data-*` PVC if it lingers after switching.)

### S3 / Pod-Identity errors (`AccessDenied`)

```bash
kubectl -n observability logs sts/mimir-ingester -c ingester --tail=100 | grep -iE "AccessDenied|forbidden|s3"
```

Mimir authenticates to S3 via **EKS Pod Identity** (ADR-047), so the `mimir` ServiceAccount has **no**
`eks.amazonaws.com/role-arn` annotation — don't look for one. Confirm the Pod Identity **association** is in
place and the associated role allows `s3:List/Get/Put/Delete` on the blocks bucket:

```bash
aws eks list-pod-identity-associations --cluster-name platform-use1-eks \
  --namespace observability --service-account mimir
```

The bucket is **AES256 (SSE-S3)** specifically so the role needs **no** KMS permissions — an SSE-KMS bucket
would require `kms:GenerateDataKey*`/`Decrypt` or every write fails with `AccessDenied` (this is why the bucket
is AES256, not KMS).

### Read path returns nothing / hangs

```bash
# query through the gateway WITH the tenant header (from inside the cluster):
kubectl -n observability exec deploy/mimir-querier -- \
  wget -qO- --header 'X-Scope-OrgID: platform' 'http://mimir-gateway.observability.svc/prometheus/api/v1/query?query=vector(1)'
# expect {"status":"success",...}. If it hangs, check query-frontend/querier/scheduler + store-gateway are Ready.
```

---

## Storage (PVCs)

- **PVC stuck `Pending`** → no usable StorageClass. The cluster-default is **gp3** (in the `eks-addons`
  unit, `create_default_storageclass`). `kubectl get sc` should show `gp3 (default)`; the deprecated in-tree
  `gp2` is present but non-default.

  ```bash
  kubectl get storageclass
  kubectl -n observability get pvc
  ```

- **Need more space** → gp3 is `allowVolumeExpansion: true`; edit the PVC's `spec.resources.requests.storage`
  (for StatefulSets, the volumeClaimTemplate change needs the operator/STS recreate — see the deadlock
  gotcha below).
- **Mimir blocks** live in S3, not a PVC — local PVCs are only the working set (WAL / compaction scratch).

---

## ⚠️ Gotchas when applying changes (Terraform/helm)

These bit us during the build — they're properties of the components, not bugs.

### 1. emptyDir → PVC storage change deadlocks `helm --wait`

`volumeClaimTemplates` are **immutable** on a StatefulSet. When you change Prometheus/Alertmanager from
emptyDir to a PVC, the **prometheus-operator deletes + recreates the StatefulSet out-of-band** (it logs
`recreating StatefulSet because the update operation wasn't possible`). The helm release update can't track
that recreation and **`helm --wait` hangs**, eventually hitting `atomic` **rollback** (which destructively
reverts to emptyDir).

- **Mitigation:** for the one-time storage migration, set `helm_wait = false` on the unit so helm doesn't
  wait on the out-of-band recreation; verify readiness manually; revert to `helm_wait = true` after.
- Verify the recreation landed: `kubectl -n observability get pvc | grep -E "prometheus|alertmanager"`
  (Bound on gp3) and the pods are 2/2.

### 2. prometheus-operator validating-webhook latency stalls helm upgrades

The operator's admission webhook validates `PrometheusRule` resources. If each webhook call is slow (~20s,
near the 30s timeout), a helm upgrade that applies ~30 bundled rules **serializes into a ~12-min "hang"** —
even with `helm_wait=false`. Confirm with a server-dry-run:

```bash
RULE=$(kubectl -n observability get prometheusrule -o name | head -1)
kubectl -n observability get "$RULE" -o yaml > /tmp/r.yaml
time kubectl apply --dry-run=server -f /tmp/r.yaml     # >~5s/rule ⇒ this is your stall
```

Inspect the webhook + operator:

```bash
kubectl get validatingwebhookconfiguration kube-prometheus-stack-admission -o yaml | grep -iE "timeout|failurePolicy|service|caBundle"
kubectl -n observability get endpoints kube-prometheus-stack-operator
```

(Root cause of the latency is still under investigation — an operator restart did **not** resolve it.
Capture findings here when known.)

### 3. Stuck helm release (`pending-upgrade`) after an interrupted apply

If a helm upgrade is killed mid-flight (e.g. you stopped a deadlocked `--wait`), the release secret is left
`pending-upgrade` and a state lock may dangle:

```bash
kubectl -n observability get secrets -l owner=helm,name=kube-prometheus-stack \
  -o custom-columns=NAME:.metadata.name,STATUS:.metadata.labels.status
```

- **The cluster config may already be applied** (helm applied the manifests before the wait) — verify the
  live `Prometheus` CR before re-running: `kubectl -n observability get prometheus kube-prometheus-stack-prometheus -o jsonpath='{.spec.remoteWrite}{.spec.storage}'`.
- **Clear it:** delete the `pending-upgrade` release secret (helm reverts its view to the last `deployed`
  revision; the cluster config is unchanged), then re-apply with `helm_wait=false`.
- **Dangling state lock:** `terragrunt force-unlock -force <LOCK_ID>` (the ID is in the
  `Error acquiring the state lock` message).
- **Orphaned processes:** `TaskStop`/Ctrl-C kills the wrapper but not child `tofu`/helm-provider processes —
  confirm none linger before re-applying.

### 4. New deploys are fine; in-place storage migrations are the hard case

On a **fresh** cluster the StatefulSets are created with gp3 from the start (no recreation, no deadlock), so
`helm_wait=true` is correct for clean bootstraps — keep it as the committed default. The gotchas above are
specific to the **in-place** emptyDir→PVC migration on a running cluster.

---

## Related

- [`../architecture/observability-current-state.md`](../architecture/observability-current-state.md) — architecture + storage model
- [`observability-access.md`](observability-access.md) — login, dashboards, queries, alerting
- [`../../infra/modules/observability/README.md`](../../infra/modules/observability/README.md) · [`../../infra/modules/observability-mimir/README.md`](../../infra/modules/observability-mimir/README.md)
- [`tailscale-vpn.md`](tailscale-vpn.md) — tailnet access
