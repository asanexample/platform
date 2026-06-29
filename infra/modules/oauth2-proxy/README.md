# oauth2-proxy

A reusable **Keycloak-SSO front** for cluster UIs that have **no native authentication**. It deploys
[oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) (Helm) in front of an in-cluster upstream,
authenticates the browser against the platform Keycloak realm over OIDC, and reverse-proxies the
upstream only after a successful login. One cluster can run several instances (one per UI) — the
`name` keys the release, Service, and synced Secret.

The first consumer is the **Argo Rollouts dashboard**
(`infra/live/aws/platform/us-east-1/platform/rollouts-sso/`): the dashboard has no auth of its own, so
the gateway-config `rollouts` HTTPRoute points at **this proxy's** Service (`rollouts`), never the
dashboard directly.

## What it provisions

When `create = true` (the default):

- `helm_release.this` — the `oauth2-proxy/oauth2-proxy` chart (`helm_chart_version`, default `7.8.2`),
  with `fullnameOverride = var.name` so the chart's Service is named exactly `var.name` (e.g.
  `rollouts`) — that name is the module's `service_name` output, which the gateway route's backend
  must match. Deployed into `var.namespace` (normally the **upstream's** namespace so the proxy reaches
  it in-cluster). The pod is Kyverno-restricted-PSA compliant (non-root, no priv-esc, RO rootfs, drop
  ALL, `RuntimeDefault`) with small fixed requests/limits.
- `kubernetes_manifest.secret` — an **ExternalSecret** (`<name>-oauth2-proxy`) that oauth2-proxy reads
  via `config.existingSecret`. It carries three keys: `client-id` (templated from `oidc_client_id`),
  `cookie-secret` (the generated cookie key, below), and `client-secret` (synced from Secrets Manager).
- `random_password.cookie` — a generated 32-byte (AES-256) cookie-signing/session key. The session
  cookie is **not** sourced from Keycloak; only the OIDC *client* secret is.
- `data.kubernetes_service_v1.gateway` — looked up only when the split-horizon host-alias is enabled
  (see below); resolves the gateway Envoy Service's ClusterIP rather than hardcoding it.

The proxy is configured (via the chart's `configFile`) as the `oidc` provider with
`reverse_proxy = true` + `set_xauthrequest`, `skip_provider_button` (straight to Keycloak), secure
cookies scoped to the `external_url` host, and the redirect URL `<external_url>/oauth2/callback`.

The module declares **no provider block** — the live unit injects the `helm` and `kubernetes`
providers (EKS exec-auth as the deployer role) and the `aws` provider from `root.hcl`.

## OIDC client-secret wiring (ESO)

The proxy needs the Keycloak **confidential client** secret, which is minted and stored in Secrets
Manager by `keycloak-config`. Rather than read it directly, the module emits an ExternalSecret so the
secret syncs in through External Secrets Operator:

- `oidc_client_secret_sm_key` — the Secrets Manager key holding the client secret (in the live unit,
  `keycloak-config`'s `client_secret_names[<client>]` output).
- `secret_store_name` — the ESO **ClusterSecretStore** to pull from (e.g. `aws-secrets-manager`).
- `oidc_client_secret_sm_property` (default `client-secret`) — `keycloak-config` stores each client as
  a JSON blob `{"client-secret":"..."}`, so the ExternalSecret extracts that **property**, not the
  whole blob.

The `client-id` and the generated `cookie-secret` are templated into the same target Secret, so all
three values oauth2-proxy needs land in one place.

## The access gate

Two independent allow-checks gate who gets in — both enforced **after** a valid Keycloak login (the
realm is the outer trust boundary):

- `allowed_groups` — Keycloak group memberships permitted in (oauth2-proxy `--allowed-group`). Empty
  (the default) means **any authenticated realm user**. Setting it requires a `groups` claim mapper on
  the client, and flips the requested OIDC scope to include `groups`.
- `email_domains` — permitted email domains (oauth2-proxy `--email-domain`). Default `["*"]` = any
  verified email; tighten to specific domains to restrict by email.

## Split-horizon issuer host-alias

On the **hub** cluster, Keycloak is served by *this* cluster's own gateway. Left alone, the proxy's
**backend** OIDC calls (token exchange, JWKS) to the issuer host would hairpin out through the internal
NLB. The `issuer_host_alias` knob avoids that by pinning the issuer hostname to the gateway Envoy
**ClusterIP** via a pod `hostAlias` (the same trick Grafana/Backstage use):

- `issuer_host_alias` — the issuer hostname to pin (e.g. `keycloak.aws.refplat.org`). **Empty (the
  default) disables it** — which is correct for **spoke** clusters that reach the hub issuer over the
  Transit Gateway normally.
- `gateway_service_name` / `gateway_service_namespace` — the Cilium Gateway-API Envoy Service to
  resolve for the ClusterIP (defaults `cilium-gateway-platform-gateway` / `default`). Used only when
  `issuer_host_alias` is set.

## Key outputs

- `service_name` — the proxy Service name (`= var.name`). Point the gateway HTTPRoute here (port 80 →
  4180), **not** at the upstream.
- `service_port` — the proxy Service port (`80`, the chart default).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | >= 2.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.this](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [kubernetes_manifest.secret](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/manifest) | resource |
| [random_password.cookie](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [kubernetes_service_v1.gateway](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/data-sources/service_v1) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_external_url"></a> [external\_url](#input\_external\_url) | Public (browser) base URL the proxy is reached at, e.g. https://rollouts.aws.refplat.org. Drives the OIDC redirect-url (<external\_url>/oauth2/callback) and the cookie domain. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Instance name — used for the release, Service, and synced Secret (e.g. "rollouts"). Lets one cluster front several UIs. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace to deploy into — normally the UPSTREAM's namespace, so the proxy reaches it in-cluster (e.g. "argo-rollouts"). | `string` | n/a | yes |
| <a name="input_oidc_client_id"></a> [oidc\_client\_id](#input\_oidc\_client\_id) | Keycloak confidential client id (registered in keycloak-config). | `string` | n/a | yes |
| <a name="input_oidc_client_secret_sm_key"></a> [oidc\_client\_secret\_sm\_key](#input\_oidc\_client\_secret\_sm\_key) | Secrets Manager key holding the OIDC client secret (keycloak-config `client_secret_names[<client>]`), synced in via ESO. | `string` | n/a | yes |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | OIDC issuer, e.g. https://keycloak.aws.refplat.org/realms/platform. | `string` | n/a | yes |
| <a name="input_secret_store_name"></a> [secret\_store\_name](#input\_secret\_store\_name) | ESO ClusterSecretStore name used to sync the client secret from Secrets Manager. | `string` | n/a | yes |
| <a name="input_upstream_url"></a> [upstream\_url](#input\_upstream\_url) | In-cluster URL of the UI to protect, e.g. http://argo-rollouts-dashboard.argo-rollouts.svc:3100. All requests pass through oauth2-proxy after auth. | `string` | n/a | yes |
| <a name="input_allowed_groups"></a> [allowed\_groups](#input\_allowed\_groups) | Keycloak group memberships allowed in (oauth2-proxy `--allowed-group`). Empty = any authenticated realm user (still gated by `email_domains`). Requires a `groups` claim mapper on the client. | `list(string)` | `[]` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether resources are created. | `bool` | `true` | no |
| <a name="input_email_domains"></a> [email\_domains](#input\_email\_domains) | Permitted email domains (oauth2-proxy `--email-domain`). "*" = any verified email; the realm itself is the trust boundary. | `list(string)` | <pre>[<br/>  "*"<br/>]</pre> | no |
| <a name="input_gateway_service_name"></a> [gateway\_service\_name](#input\_gateway\_service\_name) | Gateway-API (Cilium) Envoy Service name to resolve for the host-alias ClusterIP. Only used when issuer\_host\_alias is set. | `string` | `"cilium-gateway-platform-gateway"` | no |
| <a name="input_gateway_service_namespace"></a> [gateway\_service\_namespace](#input\_gateway\_service\_namespace) | Namespace of the gateway Envoy Service. Only used when issuer\_host\_alias is set. | `string` | `"default"` | no |
| <a name="input_helm_chart_version"></a> [helm\_chart\_version](#input\_helm\_chart\_version) | oauth2-proxy chart version (oauth2-proxy/oauth2-proxy). | `string` | `"7.8.2"` | no |
| <a name="input_helm_wait"></a> [helm\_wait](#input\_helm\_wait) | Wait for the release to become ready. | `bool` | `true` | no |
| <a name="input_issuer_host_alias"></a> [issuer\_host\_alias](#input\_issuer\_host\_alias) | Hostname of the issuer to pin to the local gateway Envoy ClusterIP (e.g. keycloak.aws.refplat.org). Empty = no host-alias (spoke clusters reaching the hub issuer over TGW). | `string` | `""` | no |
| <a name="input_oidc_client_secret_sm_property"></a> [oidc\_client\_secret\_sm\_property](#input\_oidc\_client\_secret\_sm\_property) | JSON property to extract from the SM secret. keycloak-config stores clients as {"client-secret":"..."}, so the bare secret is the `client-secret` property (NOT the whole blob). | `string` | `"client-secret"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags (sanitized into K8s labels). | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | The oauth2-proxy Service name — point the gateway HTTPRoute at this (port 80 → 4180), NOT the upstream directly. |
| <a name="output_service_port"></a> [service\_port](#output\_service\_port) | The oauth2-proxy Service port (the chart's default). |
<!-- END_TF_DOCS -->
