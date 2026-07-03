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
- **Scaffolder write App** (`enable_scaffolder`, default off): syncs the separate GitHub **write** App
  credential (`platform/backstage/scaffolder-github-app` — Contents+PRs read/write on `asanexample/platform`
  only, ADR-062 §5) and injects `SCAFFOLDER_GITHUB_APP_ID` / `SCAFFOLDER_GITHUB_APP_PRIVATE_KEY` for the
  self-service templates (BACK Phase 3).
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
- `enable_oidc` / `enable_github_discovery` / `enable_scaffolder` / `enable_kubernetes_plugin` /
  `enable_argocd_plugin` feature flags and their per-feature secret-name + cluster/instance inputs.
- `host_aliases` — split-horizon resolution of the OIDC issuer host to the in-cluster gateway.
- `cluster_name`, `region`, `deployer_role_arn`, `finalizer_clear_script` — for Pod Identity + the destroy drain.

## Key outputs

- `namespace`, `service_name`, `service_port` (7007) — the HTTPRoute backend target.
- `db_cluster_name` (in-cluster mode) and `helm_release_status`.

## Dependencies (live unit)

`eks`, `node-groups`, `cloudnative-pg`, `external-secrets`, `secret-stores`, `keycloak-config` (the OIDC client secret). No IRSA SA
annotation — AWS access is EKS Pod Identity (ADR-047). Exposure is wired by `gateway-config`.

## Related ADRs & runbooks

- ADR-051: Backstage developer portal
- `docs/runbooks/backstage-argocd.md` — minting the read-only ArgoCD token
- `docs/runbooks/backstage-github-app.md` — the read-only GitHub App credential
- `docs/runbooks/backstage-scaffolder-github-app.md` — the scaffolder's separate GitHub write App (ADR-062)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | ~> 3.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | ~> 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | ~> 3.0 |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_access_entry.k8s_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.k8s_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_pod_identity_association.k8s_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.k8s_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.k8s_reader_remote](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [helm_release.backstage](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.argocd_token_external_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.audit_db_external_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.backup_object_store](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.db](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.github_app_external_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.oidc_external_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.scaffolder_github_app_external_secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_manifest.scheduled_backup](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [kubernetes_namespace_v1.backstage](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/namespace_v1) | resource |
| [kubernetes_secret_v1.session](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [null_resource.namespace_drain](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [random_password.session](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_iam_policy_document.k8s_reader_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [kubernetes_service_v1.gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/service_v1) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | Helm chart version (pinned in \_versions.hcl) | `string` | n/a | yes |
| <a name="input_image_tag"></a> [image\_tag](#input\_image\_tag) | Backstage image tag (the asanexample/backstage commit SHA) | `string` | n/a | yes |
| <a name="input_argocd_instances"></a> [argocd\_instances](#input\_argocd\_instances) | ArgoCD instances surfaced by the plugin (rendered into argocd.appLocatorMethods). `url` is the in-cluster API the BACKEND calls (e.g. http://argocd-server.argocd.svc); `frontend_url` is the browser-facing UI used for 'open in ArgoCD' links (e.g. https://argocd.aws.refplat.org). The read-only token is injected via ARGOCD\_AUTH\_TOKEN. | <pre>list(object({<br/>    name         = string<br/>    url          = string<br/>    frontend_url = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_argocd_token_secret_key"></a> [argocd\_token\_secret\_key](#input\_argocd\_token\_secret\_key) | Key/property within the ArgoCD token Secrets Manager secret (and the synced K8s Secret / env). | `string` | `"token"` | no |
| <a name="input_argocd_token_secret_name"></a> [argocd\_token\_secret\_name](#input\_argocd\_token\_secret\_name) | Secrets Manager path holding the read-only ArgoCD API token (minted out-of-band against the `backstage` account; see docs/runbooks/backstage-argocd.md). | `string` | `"platform/argocd/backstage-token"` | no |
| <a name="input_audit_db_secret_id"></a> [audit\_db\_secret\_id](#input\_audit\_db\_secret\_id) | Secrets Manager secret id (key `uri`) holding the ADR-084 directory Postgres connection, projected into AUDIT\_DB\_DSN for the My Access view's borrow history (ADR-088 §3.6). Empty disables history. | `string` | `""` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | This (platform) EKS cluster name — for the Pod Identity association and the cluster-View access entry. | `string` | `""` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to deploy Backstage | `bool` | `true` | no |
| <a name="input_database"></a> [database](#input\_database) | Backstage database. mode = in-cluster (CloudNativePG) \| rds. For in-cluster, instances/storage\_size size the CNPG Cluster. | <pre>object({<br/>    mode         = optional(string, "in-cluster")<br/>    instances    = optional(number, 1)<br/>    storage_size = optional(string, "5Gi")<br/>    # Barman Cloud backups (#1119) for the in-cluster CNPG DB. enable_backups attaches the WAL archiver +<br/>    # creates the ObjectStore and a daily ScheduledBackup (rolls the instance once). destination_path must be<br/>    # the BUCKET ROOT (barman appends the server name = cluster) and match the cluster's Pod-Identity role scope.<br/>    enable_backups   = optional(bool, false)<br/>    destination_path = optional(string, "")<br/>    retention        = optional(string, "30d")<br/>    schedule         = optional(string, "0 0 3 * * *")<br/>  })</pre> | `{}` | no |
| <a name="input_db_cluster_name"></a> [db\_cluster\_name](#input\_db\_cluster\_name) | Name of the CloudNativePG Cluster (in-cluster mode). CNPG creates <name>-rw Service + <name>-app Secret. | `string` | `"backstage-db"` | no |
| <a name="input_deployer_role_arn"></a> [deployer\_role\_arn](#input\_deployer\_role\_arn) | IAM role ARN to assume for the destroy-time namespace drain (the PlatformDeployer) | `string` | `""` | no |
| <a name="input_enable_argocd_plugin"></a> [enable\_argocd\_plugin](#input\_enable\_argocd\_plugin) | Enable the Backstage ArgoCD plugin: inject the argocd app-config (appLocatorMethods/instances) + sync the read-only ArgoCD token into ARGOCD\_AUTH\_TOKEN. | `bool` | `false` | no |
| <a name="input_enable_github_discovery"></a> [enable\_github\_discovery](#input\_enable\_github\_discovery) | Sync the read-only GitHub App credential (github\_app\_secret\_name) into the namespace and inject it as GITHUB\_APP\_ID/GITHUB\_APP\_PRIVATE\_KEY. The image's app-config wires integrations.github.apps + catalog.providers.github. | `bool` | `true` | no |
| <a name="input_enable_kubernetes_plugin"></a> [enable\_kubernetes\_plugin](#input\_enable\_kubernetes\_plugin) | Enable the Backstage Kubernetes plugin: create the EKS Pod Identity reader role + this-cluster access entry and inject the kubernetes app-config layer. | `bool` | `false` | no |
| <a name="input_enable_oidc"></a> [enable\_oidc](#input\_enable\_oidc) | Wire OIDC SSO: sync the Keycloak `backstage` client secret into the namespace as OIDC\_CLIENT\_SECRET + generate the Backstage session-signing secret (AUTH\_SESSION\_SECRET). The image's app-config.production.yaml configures the direct-Keycloak `oidc` provider. | `bool` | `true` | no |
| <a name="input_enable_scaffolder"></a> [enable\_scaffolder](#input\_enable\_scaffolder) | Sync the scaffolder's GitHub WRITE App credential (scaffolder\_github\_app\_secret\_name) into the namespace and inject it as SCAFFOLDER\_GITHUB\_APP\_ID/SCAFFOLDER\_GITHUB\_APP\_PRIVATE\_KEY. The image's app-config wires it as the second integrations.github.apps entry (the App is installed on asanexample/platform only). See docs/runbooks/backstage-scaffolder-github-app.md. | `bool` | `false` | no |
| <a name="input_finalizer_clear_script"></a> [finalizer\_clear\_script](#input\_finalizer\_clear\_script) | Non-empty enables the destroy-time teardown cleanup script. Only checked for non-emptiness — the script itself is resolved at run time via the checkout's own `git rev-parse --show-toplevel`, not this value, so a worktree's different absolute path can't force a spurious null\_resource replace. Kept as a path-shaped string for unit-wiring compatibility (units still pass get\_repo\_root()). | `string` | `""` | no |
| <a name="input_gateway_service_name"></a> [gateway\_service\_name](#input\_gateway\_service\_name) | Name of the Cilium gateway LoadBalancer Service whose ClusterIP backs oidc\_gateway\_alias\_host. | `string` | `"cilium-gateway-platform-gateway"` | no |
| <a name="input_gateway_service_namespace"></a> [gateway\_service\_namespace](#input\_gateway\_service\_namespace) | Namespace of the Cilium gateway Service (the shared Gateway lives in `default`). | `string` | `"default"` | no |
| <a name="input_github_app_secret_name"></a> [github\_app\_secret\_name](#input\_github\_app\_secret\_name) | Secrets Manager path holding the GitHub App credential as JSON {appId, privateKey}. Created manually; see docs/runbooks/backstage-github-app.md. | `string` | `"platform/backstage/github-app"` | no |
| <a name="input_helm_chart"></a> [helm\_chart](#input\_helm\_chart) | Helm chart name | `string` | `"backstage"` | no |
| <a name="input_helm_release_name"></a> [helm\_release\_name](#input\_helm\_release\_name) | Helm release name | `string` | `"backstage"` | no |
| <a name="input_helm_repository"></a> [helm\_repository](#input\_helm\_repository) | Helm chart repository | `string` | `"https://backstage.github.io/charts"` | no |
| <a name="input_helm_timeout"></a> [helm\_timeout](#input\_helm\_timeout) | Helm release timeout (seconds) | `number` | `600` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. Default false: the DB Cluster provisions async, so we verify pod health out of band rather than risk a wait timeout. | `bool` | `false` | no |
| <a name="input_host_aliases"></a> [host\_aliases](#input\_host\_aliases) | Extra pod /etc/hosts entries (in addition to the dynamically-resolved oidc\_gateway\_alias\_host). | <pre>list(object({<br/>    ip        = string<br/>    hostnames = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_image_registry"></a> [image\_registry](#input\_image\_registry) | ECR registry host for the Backstage image | `string` | `"829808296602.dkr.ecr.us-east-1.amazonaws.com"` | no |
| <a name="input_image_repository"></a> [image\_repository](#input\_image\_repository) | ECR repository for the Backstage image | `string` | `"platform/backstage"` | no |
| <a name="input_kubernetes_clusters"></a> [kubernetes\_clusters](#input\_kubernetes\_clusters) | Clusters surfaced by the Kubernetes plugin (rendered into the kubernetes app-config). authProvider is always aws; set assume\_role for cross-account clusters. | <pre>list(object({<br/>    name        = string<br/>    url         = string<br/>    ca_data     = string<br/>    region      = optional(string, "us-east-1")<br/>    assume_role = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace for Backstage | `string` | `"backstage"` | no |
| <a name="input_oidc_gateway_alias_host"></a> [oidc\_gateway\_alias\_host](#input\_oidc\_gateway\_alias\_host) | Hostname to pin (via /etc/hosts) to the in-cluster Cilium gateway ClusterIP — the OIDC issuer host<br/>(keycloak.aws.refplat.org). The backend's OIDC discovery + token exchange then hit the gateway's Envoy<br/>directly instead of the public name's internal-NLB hairpin (which is flaky), while TLS still validates<br/>(wildcard cert at the gateway). The ClusterIP is looked up dynamically from the gateway Service — NOT<br/>hardcoded — so it self-corrects on every apply if the Service is recreated. Empty = no alias. | `string` | `""` | no |
| <a name="input_oidc_secret_key"></a> [oidc\_secret\_key](#input\_oidc\_secret\_key) | Key/property within the OIDC Secrets Manager secret (and the synced K8s Secret). | `string` | `"client-secret"` | no |
| <a name="input_oidc_secret_name"></a> [oidc\_secret\_name](#input\_oidc\_secret\_name) | Secrets Manager path holding the Keycloak OIDC client secret (the `backstage` confidential client, created by keycloak-config). | `string` | `"platform/keycloak/backstage-oidc"` | no |
| <a name="input_projection_mode"></a> [projection\_mode](#input\_projection\_mode) | platform-projection catalog mode (ADR-067). "" leaves the image default (v2). Set "v3" at the cutover to project Product=System / Environment=custom-kind (no new image needed — the L2c frontend ships in the image). | `string` | `""` | no |
| <a name="input_rds_host"></a> [rds\_host](#input\_rds\_host) | RDS Postgres endpoint host (rds mode). | `string` | `""` | no |
| <a name="input_rds_secret_name"></a> [rds\_secret\_name](#input\_rds\_secret\_name) | Name of the K8s Secret (ExternalSecret-synced) holding username/password for RDS (rds mode). | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster (for destroy-time namespace drain auth) | `string` | `""` | no |
| <a name="input_remote_cluster_role_arns"></a> [remote\_cluster\_role\_arns](#input\_remote\_cluster\_role\_arns) | Cross-account read-only Backstage role ARNs the reader role may assume (e.g. the preprod Backstage role) for the Kubernetes plugin. | `list(string)` | `[]` | no |
| <a name="input_replica_count"></a> [replica\_count](#input\_replica\_count) | Backstage backend replicas | `number` | `1` | no |
| <a name="input_resources"></a> [resources](#input\_resources) | Backstage backend container resource requests/limits | <pre>object({<br/>    requests = optional(map(string), { cpu = "250m", memory = "512Mi" })<br/>    limits   = optional(map(string), { cpu = "1", memory = "1Gi" })<br/>  })</pre> | `{}` | no |
| <a name="input_scaffolder_github_app_secret_name"></a> [scaffolder\_github\_app\_secret\_name](#input\_scaffolder\_github\_app\_secret\_name) | Secrets Manager path holding the scaffolder GitHub write App credential as JSON {appId, privateKey}. Created manually; see docs/runbooks/backstage-scaffolder-github-app.md. | `string` | `"platform/backstage/scaffolder-github-app"` | no |
| <a name="input_secret_store_name"></a> [secret\_store\_name](#input\_secret\_store\_name) | Name of the ClusterSecretStore (External Secrets) to read Secrets Manager. | `string` | `"aws-secrets-manager"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags (rendered as pod labels) | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_cluster_name"></a> [db\_cluster\_name](#output\_db\_cluster\_name) | CloudNativePG Cluster name (in-cluster DB mode), else null |
| <a name="output_helm_release_status"></a> [helm\_release\_status](#output\_helm\_release\_status) | Status of the Backstage Helm release |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace where Backstage is deployed |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Backstage Service name (HTTPRoute backend target) |
| <a name="output_service_port"></a> [service\_port](#output\_service\_port) | Backstage Service port |
<!-- END_TF_DOCS -->