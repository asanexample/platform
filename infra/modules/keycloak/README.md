# keycloak

Deploys **Keycloak** — the app-facing OIDC identity provider (ADR-053) — as a Tier-0 stateful service on the
platform cluster, **alongside Dex** (ADR-052). This is delivery-plan **B1: deploy-only**. Keycloak runs, is
HA-capable, CNPG-backed, and exposed internally; the realm, the Identity Center SAML broker, per-app OIDC
clients, and group/role mappers (the access-model-as-code) are **B2** and are NOT configured here.

## What it provisions

- **Namespace** `keycloak` (PSA-labelled), with a hardened pod (runAsNonRoot, drop ALL, seccomp RuntimeDefault).
- **Keycloak** via the `codecentric/keycloakx` Helm chart on the official `quay.io/keycloak/keycloak` image,
  pinned to the **latest stable Keycloak (26.6.3)** via an image-tag override. Runs production mode
  (`kc.sh start`), behind the Cilium gateway (TLS terminates there → `KC_HTTP_ENABLED`, `KC_PROXY_HEADERS=xforwarded`,
  `KC_HOSTNAME`). Single replica for B1 (the chart's `jdbc-ping` cache makes HA a later replica bump — no extra
  discovery wiring).
- **Postgres** via a CloudNativePG `Cluster` (in-cluster; `database.mode = rds` is the deferred toggle). CNPG
  creates `<cluster>-rw` + `<cluster>-app`; the chart's `dbchecker` waits for it before boot. Backups deferred
  to ADR-054.
- **Admin credential** generated here, stored in Secrets Manager (`platform/keycloak/admin`), synced into the
  namespace as `keycloak-admin` by External Secrets, and consumed as `KC_BOOTSTRAP_ADMIN_*`.

## Usage

```hcl
module "keycloak" {
  source             = "../../modules/keycloak"
  helm_chart_version = "7.2.0" # codecentric/keycloakx (Keycloak 26.6.3 via image tag)
  tags               = local.tags
}
```

Exposure is wired by the `gateway-config` unit (a `keycloak` route → `keycloak.aws.refplat.org`, internal NLB,
cert-manager TLS). Outputs `namespace` / `service_name` / `service_port` / `issuer` feed it.

## Dependencies (live unit)

`eks`, `node-groups`, `external-secrets`, `secret-stores`, `cloudnative-pg`. No Pod Identity / IRSA — Keycloak
needs no AWS API at runtime (the admin secret arrives via ESO's IRSA; the DB is in-cluster).

## Not here (→ B2)

Realm, Identity Center SAML broker, per-app OIDC clients, group/role mappers, the access-model-as-code
generation from the Team model, and the Dex→Keycloak issuer cutover. Dex is untouched.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [helm_release.keycloak](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.admin_external_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.db](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.http_redirect_route](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.http_route](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.keycloak](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [random_password.admin](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Helm chart version (pinned in \_versions.hcl) | `string` | n/a | yes |
| <a name="input_admin_username"></a> [admin\_username](#input\_admin\_username) | Bootstrap admin username | `string` | `"admin"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to deploy Keycloak | `bool` | `true` | no |
| <a name="input_create_route"></a> [create\_route](#input\_create\_route) | Create Keycloak's HTTPRoute (+ HTTP→HTTPS redirect) on the shared Gateway. Off by default; the unit enables it (needs the gateway dependency). | `bool` | `false` | no |
| <a name="input_database"></a> [database](#input\_database) | Keycloak database. mode = in-cluster (CloudNativePG) \| rds. For in-cluster, instances/storage\_size size the CNPG Cluster. | <pre>object({<br/>    mode         = optional(string, "in-cluster")<br/>    instances    = optional(number, 1)<br/>    storage_size = optional(string, "8Gi")<br/>  })</pre> | `{}` | no |
| <a name="input_db_cluster_name"></a> [db\_cluster\_name](#input\_db\_cluster\_name) | Name of the CloudNativePG Cluster (in-cluster mode). CNPG creates <name>-rw Service + <name>-app Secret. | `string` | `"keycloak-db"` | no |
| <a name="input_gateway_name"></a> [gateway\_name](#input\_gateway\_name) | Name of the shared Gateway to attach Keycloak's HTTPRoute to (parentRef). | `string` | `"platform-gateway"` | no |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace of the shared Gateway (parentRef). | `string` | `"default"` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name | `string` | `"keycloakx"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name | `string` | `"keycloak"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm chart repository | `string` | `"https://codecentric.github.io/helm-charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm release timeout (seconds) | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. Default false: the admin secret syncs async via External Secrets and the DB must come up first; verify health out of band. | `bool` | `false` | no |
| <a name="input_hostname_url"></a> [hostname\_url](#input\_hostname\_url) | Public base URL Keycloak serves on (KC\_HOSTNAME). Behind the gateway at keycloak.aws.refplat.org for now; becomes sso.aws.refplat.org at the Dex cutover. | `string` | `"https://keycloak.aws.refplat.org"` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | Keycloak image repository | `string` | `"quay.io/keycloak/keycloak"` | no |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Keycloak image tag (the Keycloak version). Defaults to the latest stable; overrides the chart appVersion. | `string` | `"26.6.3"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for Keycloak | `string` | `"keycloak"` | no |
| <a name="input_rds_host"></a> [rds\_host](#input\_rds\_host) | RDS Postgres hostname (rds mode). | `string` | `""` | no |
| <a name="input_rds_secret_name"></a> [rds\_secret\_name](#input\_rds\_secret\_name) | K8s Secret name holding RDS username/password (rds mode). | `string` | `""` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Keycloak replicas. 1 for B1 (no clustering). HA (2+) additionally requires Infinispan/JGroups discovery (KC\_CACHE=ispn + KUBE\_PING) — a follow-up. | `number` | `1` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Keycloak container resource requests/limits (JVM — size memory generously). | <pre>object({<br/>    requests = optional(map(string), { cpu = "500m", memory = "1Gi" })<br/>    limits   = optional(map(string), { cpu = "2", memory = "2Gi" })<br/>  })</pre> | `{}` | no |
| <a name="input_secret_recovery_window_days"></a> [secret\_recovery\_window\_days](#input\_secret\_recovery\_window\_days) | Secrets Manager recovery window for the generated admin secret. 0 = force-delete (setup-friendly); raise for prod. | `number` | `0` | no |
| <a name="input_secret_store_name"></a> [secret\_store\_name](#input\_secret\_store\_name) | Name of the ClusterSecretStore (External Secrets) to read Secrets Manager. | `string` | `"aws-secrets-manager"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags (applied to Secrets Manager secrets; rendered as pod labels) | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_issuer"></a> [issuer](#output\_issuer) | OIDC issuer base URL (realms live at <issuer>/realms/<realm>) |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Keycloak namespace |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Keycloak Service name (gateway-config route backend) |
| <a name="output_service_port"></a> [service\_port](#output\_service\_port) | Keycloak Service HTTP port (gateway-config route backend port) |
<!-- END_TF_DOCS -->