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
