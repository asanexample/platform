# dex

Deploys **Dex** (`dexidp/dex` chart) — the centralized **SAML→OIDC broker** (ADR-052). Dex federates AWS
Identity Center (a SAML connector) and re-exposes it as a single OIDC issuer that first-party apps (Backstage,
and any other `static_clients` entry) authenticate against. TLS terminates at the Cilium Gateway; Dex serves
plaintext HTTP on `5556` behind it.

> **LEGACY.** Per ADR-053, Dex is being superseded by **Keycloak** as the app-facing IdP of record. Dex is
> retained today because it still serves Backstage's OIDC SSO; new wiring (e.g. oauth2-proxy) points at Keycloak.

## What it deploys

- **Namespace** `dex` (hardened pod: runAsNonRoot, readOnlyRootFilesystem with a writable `/tmp` emptyDir, drop
  ALL, seccomp RuntimeDefault; an ingress-only NetworkPolicy).
- **Dex** Helm release, `ClusterIP` on `5556`, `replicaCount` default **2** for stateless HA (storage is
  `kubernetes`/CRD-backed — `rbac.createClusterScoped` lets Dex manage its own `dex.coreos.com` CRDs, shared
  across replicas). No local password DB; trusted clients skip the consent screen.
- A **SAML connector** (`aws-sso`) to Identity Center — `usernameAttr`/`emailAttr = email`, `groupsAttr = groups`.
  The connector's redirect/ACS is `<dex_issuer>/callback`.
- **Per-client OIDC secrets**: for each `static_clients` entry a 40-char secret is generated, stored in Secrets
  Manager at `platform/<id>/oidc`, synced into the namespace as `dex-<id>-oidc` by External Secrets, and injected
  into Dex via the client's `secretEnv`. Default client is `backstage`.

## Key inputs

- `helm_chart_version` (required), `saml_sso_url` + `saml_ca_data` (required, from `secrets.hcl`).
- `dex_issuer` (default `https://sso.aws.refplat.org`) — the public OIDC issuer URL.
- `static_clients` — list of `{ id, name, redirect_uris, secret_env }`; add an entry to onboard another app.
- `image_tag` / `image_digest` (optional pins; empty inherits the chart's appVersion), `replica_count`,
  `secret_store_name`, `secret_recovery_window_days`.

## Outputs

- `namespace`, `service_name`, `service_port` (5556) — the `gateway-config` route backend.
- `issuer` — the OIDC issuer URL.

## Dependencies (live unit)

`eks`, `node-groups`, `external-secrets`, `secret-stores`. Exposure (the `sso` route) is wired by `gateway-config`.

## Related ADRs & runbooks

- ADR-052: centralized Dex SSO broker
- ADR-053: identity & cross-system authorization strategy (the Keycloak supersession)
- `docs/runbooks/dex-sso.md` — SAML app setup, issuer/ACS config, image-digest resolution
