# observability-tenant-proxy (P13 read isolation — enforcement point)

Deploys the [`tenant-proxy`](../../../services/tenant-proxy) service and the Grafana datasource that
routes through it. This is the **read** half of P13 per-team isolation (#590): the
[`observability-cortex-tenant`](../observability-cortex-tenant) write side lands each team's metrics
in its own Mimir tenant, and this makes Grafana query **only the caller's team tenant**.

```text
user → Grafana ──(query + X-Id-Token, oauthPassThru)──▶ tenant-proxy ──(X-Scope-OrgID=<team[s]>)──▶ Mimir
```

The proxy verifies the Grafana-forwarded OIDC token against the realm JWKS, maps the `groups` claim
to a tenant scope (admin group → all tenants; unknown/empty → **deny**), overwrites `X-Scope-OrgID`,
and reverse-proxies to the Mimir gateway. Fail-closed: no valid token → no data. Full behaviour +
tests: the service README.

## What it creates

- A **Deployment** (digest-pinned signed image, non-root, read-only rootfs) + **Service** (`:8080`
  proxy, `:9090` metrics/health) + **ServiceMonitor** (`tenant_proxy_requests_total`).
- The **`Mimir (my team)` Grafana datasource** (`grafana_datasource=1` ConfigMap) with
  `oauthPassThru: true` → the proxy. This is the enforcement point users pick in Explore/dashboards.

## Config notes

- **JWKS via the in-cluster keycloak service** (`keycloak-http.keycloak.svc`) to avoid the
  in-cluster→internal-NLB hairpin. The token's `iss` (`oidc_issuer`) is still the **public** realm URL
  — go-oidc checks the issuer string independently of where the keys are fetched.
- **`tenants`** is the known team-tenant set; a user's groups are intersected with it, so an unknown
  group can never widen access. **`admin_group`** (`platform-admins`) gets the federated all-tenant read.

## Status / how it fits

Gated by `enable_per_team_tenants`. Depends on: the signed image (`tenant-proxy-image.yml` → ADR-071
digest pin) and the per-team tenants being populated (the cortex-tenant write side). Admin overview
stays on the existing `Mimir (all clusters)` datasource; this adds the per-user team-scoped lane.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_config_map_v1.datasource](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [kubernetes_deployment_v1.tenant_proxy](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1) | resource |
| [kubernetes_manifest.tenant_proxy_service_monitor](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_service_v1.tenant_proxy](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_image"></a> [image](#input\_image) | The signed tenant-proxy image, digest-pinned (registry/repo@sha256:…). Built by tenant-proxy-image.yml, ADR-071 digest-pin. | `string` | n/a | yes |
| <a name="input_admin_group"></a> [admin\_group](#input\_admin\_group) | The group granting the federated all-tenant read (platform-admins → sees every tenant). | `string` | `"platform-admins"` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created (the P13 read-isolation toggle — enable\_per\_team\_tenants). | `bool` | `false` | no |
| <a name="input_create_datasource"></a> [create\_datasource](#input\_create\_datasource) | Create the per-team Grafana datasource ConfigMap (oauthPassThru → the proxy). True on the hub that runs Grafana. | `bool` | `true` | no |
| <a name="input_create_service_monitor"></a> [create\_service\_monitor](#input\_create\_service\_monitor) | Scrape the proxy's own decision metrics (tenant\_proxy\_requests\_total). | `bool` | `true` | no |
| <a name="input_datasource_name"></a> [datasource\_name](#input\_datasource\_name) | Display name of the per-team Grafana datasource. | `string` | `"Mimir (my team)"` | no |
| <a name="input_grants"></a> [grants](#input\_grants) | Cross-team read grants (ADR-068 AccessGrant projection): grantee team group → the owner tenants it may ADDITIONALLY read on top of its own. E.g. { bravo = ["alpha"] } lets group `bravo` read alpha's tenant (federated `X-Scope-OrgID: alpha|bravo`). Rendered into the proxy's GRANTS env; the proxy drops any owner that isn't a known tenant (a grant never invents a scope). Derived at the unit from gitops/grants, excluding regulated (pci/hipaa) targets. Empty = no cross-team sharing (own-tenant-only). | `map(list(string))` | `{}` | no |
| <a name="input_jwks_url"></a> [jwks\_url](#input\_jwks\_url) | Keycloak realm JWKS endpoint. Use the IN-CLUSTER keycloak service to avoid the in-cluster→internal-NLB hairpin — the token's `iss` (oidc\_issuer) is still the public realm URL, checked independently of where the keys are fetched. | `string` | `"http://keycloak-http.keycloak.svc/realms/platform/protocol/openid-connect/certs"` | no |
| <a name="input_name"></a> [name](#input\_name) | Instance name (Deployment/Service/selector). One proxy per signal — `tenant-proxy` (metrics), `loki-tenant-proxy` (logs), `tempo-tenant-proxy` (traces), `pyroscope-tenant-proxy` (profiles) — each fronting its store via `upstream_url`. The resolver/grant logic is identical; only the upstream differs. | `string` | `"tenant-proxy"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into (the shared observability namespace, next to Grafana + Mimir). | `string` | `"observability"` | no |
| <a name="input_oidc_audience"></a> [oidc\_audience](#input\_oidc\_audience) | The `aud` the token must contain — the Grafana OIDC client id. | `string` | `"grafana"` | no |
| <a name="input_oidc_issuer"></a> [oidc\_issuer](#input\_oidc\_issuer) | The exact `iss` the token must carry — the PUBLIC realm URL Keycloak stamps into tokens. | `string` | `"https://keycloak.aws.refplat.org/realms/platform"` | no |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | tenant-proxy replicas. On the read path, so run >=2. | `number` | `2` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Labels to apply. | `map(string)` | `{}` | no |
| <a name="input_tenants"></a> [tenants](#input\_tenants) | Known team tenants the proxy may scope to (comma-joined into the proxy's TENANTS). A user's groups are intersected with this set; unknown groups can't widen access. | `list(string)` | <pre>[<br/>  "alpha",<br/>  "bravo",<br/>  "platform"<br/>]</pre> | no |
| <a name="input_upstream_url"></a> [upstream\_url](#input\_upstream\_url) | The store query API the proxy reverse-proxies to (per-request X-Scope-OrgID). The in-cluster Mimir gateway /prometheus. | `string` | `"http://mimir-gateway.observability.svc/prometheus"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_query_url"></a> [query\_url](#output\_query\_url) | In-cluster URL of the tenant-proxy (what the per-team Grafana datasource points at). Null when disabled. |
<!-- END_TF_DOCS -->
