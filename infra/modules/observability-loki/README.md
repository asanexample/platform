# observability-loki

Observability **P3a** — the multi-tenant **logs** store for the platform hub (`docs/plans/102-observability-stack.md`).
Deploys `grafana/loki` into the `observability` namespace, S3-backed, and registers a Grafana **Loki** datasource
(with a `trace_id` derived field that links a log line to its Tempo trace). Mirrors `observability-mimir` (P2); the
only structural difference is **identity**.

## Key decisions

- **EKS Pod Identity, not IRSA** (ADR-047). The module creates an IAM role trusting `pods.eks.amazonaws.com` and an
  `aws_eks_pod_identity_association` binding (`namespace`, ServiceAccount `loki`) → role. No OIDC provider inputs, no
  `eks.amazonaws.com/role-arn` annotation. (The rest of the observability stack has likewise migrated to EKS Pod
  Identity — ADR-047/#594.)
- **SingleBinary by default**, `SimpleScalable` (read/write/backend RF3) when `high_availability = true` — one toggle,
  same pattern as Mimir/Tempo.
- **S3 chunks** bucket created in-module (SSE-S3/AES256, versioned, lifecycle); IAM scoped to that bucket only.
- **Multitenancy on** (`auth_enabled`): `X-Scope-OrgID` required. In-cluster isolation rests on the `observability`
  namespace default-deny NetworkPolicy (tenant pods can't reach the store). Per-tenant limits double as the
  noisy-neighbor control. Retention (default 14d) enforced by the compactor.

## Key inputs

| Input | Default | Notes |
|-------|---------|-------|
| `cluster_name` | — | S3 + IAM naming + the Pod Identity association |
| `namespace` | `observability` | must pre-exist (observability module) |
| `helm_chart_version` | `7.0.0` | pinned in `_versions.hcl` |
| `high_availability` | `false` | SingleBinary ↔ SimpleScalable RF3 |
| `retention_period` | `336h` (14d) | compactor-enforced |
| `default_tenant_id` | `platform` | the hub's own logs |

## Gotchas

- The chart **requires** a `loki.schemaConfig` (tsdb / schema v13) — omitting it fails the release. Provided here.
- Collectors (Alloy) write to this store; they ship in the P3a log-pipeline unit, not here.
