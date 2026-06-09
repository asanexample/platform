# oauth2-proxy

Deploys **oauth2-proxy** (`oauth2-proxy/oauth2-proxy` chart) as the authenticating reverse proxy in front of
**Backstage** (#202). The Cilium Gateway routes `backstage.aws.refplat.org` → oauth2-proxy → Backstage:7007.
The proxy owns the session cookie and injects validated identity headers, which fixes Backstage's
logout-on-refresh: Identity Center / the IdP issue no refresh token, so `cookie-refresh` is hard-set to `0` and
the encrypted+signed cookie stays valid for `cookie_expire` (a durable session).

## What it deploys

- An **oauth2-proxy** Helm release in the **`backstage` namespace** (owned by the `backstage` module — this
  module does **not** create the namespace). `replicaCount` default **2** (cookie session storage is stateless,
  shared `cookie-secret`). Listens on `service_port` (default `4180`), the `gateway-config` route backend.
- **OIDC provider** config: `oidc_issuer_url` (the **Keycloak** realm by default, ADR-053/059; was Dex
  pre-cutover), `oidc_client_id`, redirect `https://<app_host>/oauth2/callback`. `set-xauthrequest` +
  `pass-user-headers` inject `X-Forwarded-*` / `X-Auth-Request-*` from the validated session (oauth2-proxy strips
  any client-supplied copies first), which Backstage's `oauth2Proxy` provider trusts — hence the backstage chart
  also locks `:7007` to this pod by NetworkPolicy.
- **Cookie secret** (`random_password`, 32 bytes → AES-256) stored in Secrets Manager at
  `platform/<release>/cookie`.
- An **ExternalSecret** that assembles the chart's `existingSecret` with three keys: `client-id` (literal),
  `client-secret` (the OIDC client secret from `client_secret_name`), and `cookie-secret` (the generated one).

## Key inputs

- `helm_chart_version` (required; must resolve to appVersion **>= 7.15.2**, CVE-2026-40575).
- `oidc_issuer_url`, `oidc_client_id`, `app_host`, `upstream_service` / `upstream_port` (Backstage 7007),
  `service_port`, `cookie_expire` (default `24h`), `email_domains` (default `["*"]`).
- `client_secret_name` / `client_secret_key`, `secret_store_name`, `host_aliases` (split-horizon to the
  in-cluster gateway).

## Outputs

- `namespace`, `service_name`, `service_port` — the gateway-config route backend.
- `pod_app_label` — the `app.kubernetes.io/name` label the backstage NetworkPolicy `podSelector` uses to lock
  `backstage:7007` to this proxy.

## Dependencies (live unit)

`eks`, `node-groups`, `external-secrets`, `secret-stores`, `dex`/keycloak (the OIDC client secret), `backstage`
(owns the namespace + upstream).

## Related runbooks / issues

- Issue #202: durable sessions / logout-on-refresh fix
- `docs/runbooks/dex-sso.md` — the SSO chain context
