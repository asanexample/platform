# cloudnative-pg

Installs the **CloudNativePG (CNPG) operator** via the `cloudnative-pg/cloudnative-pg` Helm chart. CNPG is the
in-cluster Postgres control plane (ADR-051): it watches `postgresql.cnpg.io` `Cluster` CRs and provisions the
backing databases for **Backstage** and **Keycloak** (each module creates its own `Cluster`; this module only
installs the operator, not any database). For each `Cluster` CNPG creates a `<name>-rw` Service (read-write
primary) and a `<name>-app` Secret (owner user/password/dbname).

## What it deploys

- The CNPG operator Helm release (default release `cnpg` in the `cnpg-system` namespace, `create_namespace = true`).
- **Webhook on hostNetwork** (`webhook_host_network`, default `true`): on the EKS + Cilium cluster-pool overlay
  the managed control plane can't route to overlay pod IPs, so the admission webhook server runs on the node VPC
  IP. The webhook host port is moved to **9446** (off Kyverno's 9443/9444), `dnsPolicy` is set to
  `ClusterFirstWithHostNet`, and the operator's `:8080` metrics server is disabled (`--metrics-bind-address=0`)
  to avoid a host-port collision. Set `webhook_host_network = false` to use the chart defaults (port 9443, no
  hostNetwork).

## Key inputs

- `helm_chart_version` (required, pinned in `_versions.hcl`).
- `webhook_host_network` (default `true`) — see above.
- `replica_count` (operator controller replicas; leader-elected, 1 is fine for non-prod), `namespace`,
  `helm_wait` (default `true`).

## Outputs

- `namespace` — where the operator runs.
- `helm_release_status`.

## Dependencies (live unit)

`eks`, `node-groups`. Must be installed before the `backstage` and `keycloak` units (which depend on it for
their `Cluster` CRs).

## Related ADRs

- ADR-051: Backstage developer portal (introduces the CNPG-backed DB pattern)
