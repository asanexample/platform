# backstage

Deploys **Backstage** — the developer portal (ADR-051) — via the official `backstage/backstage` Helm chart,
running the platform's own image from ECR (`platform/backstage`, built + signed by the `asanexample/backstage`
repo CI). The module owns the `backstage` namespace and wires the portal's data plane (Postgres), SSO, GitHub
catalog discovery, and the live Kubernetes / ArgoCD plugins.

## What it deploys

- **Namespace** `backstage` (hardened pod: runAsNonRoot, drop ALL, seccomp RuntimeDefault).
- **Backstage** Helm release on port `7007`, `ClusterIP` (ingress is the Cilium Gateway via a `gateway-config`
  HTTPRoute, not a K8s Ingress). The chart's bundled bitnami Postgres is disabled. No ingress NetworkPolicy —
  Backstage authenticates each request itself via direct Keycloak OIDC, so the gateway routes to it directly.
- **Postgres**: in-cluster via a CloudNativePG `Cluster` (`<db_cluster_name>-rw` Service + `<db_cluster_name>-app`
  Secret; a managed `backstage` role with `CREATEDB` for per-plugin DBs) — `database.mode = rds` is the prod toggle.
- **OIDC SSO** (`enable_oidc`): syncs the **Keycloak** `backstage` client secret
  (`platform/keycloak/backstage-oidc`, created by keycloak-config) via External Secrets and injects
  `OIDC_CLIENT_SECRET` + a TF-generated `AUTH_SESSION_SECRET`. The image's app-config wires the direct-Keycloak
  `oidc` sign-in provider. See [identity-and-sso](../../../docs/architecture/identity-and-sso.md).
- **GitHub catalog discovery** (`enable_github_discovery`): syncs the read-only GitHub App credential
  (`platform/backstage/github-app`) and injects `GITHUB_APP_ID` / `GITHUB_APP_PRIVATE_KEY`.
- **Kubernetes plugin** (`enable_kubernetes_plugin`, default off): an EKS Pod Identity reader role
  (AmazonEKSViewPolicy) on this cluster, plus assume-role into cross-account read-only Backstage roles, with the
  `kubernetes` app-config rendered from `kubernetes_clusters`.
- **ArgoCD plugin** (`enable_argocd_plugin`, default off): the read-only ArgoCD token
  (`platform/argocd/backstage-token`) injected as `ARGOCD_AUTH_TOKEN`, plus the `argocd` app-config from
  `argocd_instances`.
- A destroy-time **namespace drain** (`null_resource`) that deletes the CNPG Cluster + force-evicts stuck pods
  so the namespace doesn't hang in Terminating on teardown.

## Key inputs

- `image_tag` (required), `helm_chart_version` (required) — the image tag is the `asanexample/backstage` commit SHA.
- `database` (`mode` / `instances` / `storage_size`), `db_cluster_name`, or `rds_host` + `rds_secret_name`.
- `enable_oidc` / `enable_github_discovery` / `enable_kubernetes_plugin` / `enable_argocd_plugin` feature flags
  and their per-feature secret-name + cluster/instance inputs.
- `host_aliases` — split-horizon resolution of the OIDC issuer host to the in-cluster gateway.
- `cluster_name`, `region`, `deployer_role_arn`, `finalizer_clear_script` — for Pod Identity + the destroy drain.

## Outputs

- `namespace`, `service_name`, `service_port` (7007) — the HTTPRoute backend target.
- `db_cluster_name` (in-cluster mode) and `helm_release_status`.

## Dependencies (live unit)

`eks`, `node-groups`, `cloudnative-pg`, `external-secrets`, `secret-stores`, `keycloak-config` (the OIDC client secret). No IRSA SA
annotation — AWS access is EKS Pod Identity (ADR-047). Exposure is wired by `gateway-config`.

## Related ADRs & runbooks

- ADR-051: Backstage developer portal
- `docs/runbooks/backstage-argocd.md` — minting the read-only ArgoCD token
- `docs/runbooks/backstage-github-app.md` — the read-only GitHub App credential
