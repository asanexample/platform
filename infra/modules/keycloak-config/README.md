# keycloak-config

Configures a running **Keycloak** (deployed by the [`keycloak`](../keycloak/) module) via the official
`keycloak/keycloak` Terraform provider — the access-model-as-code (ADR-053). It provisions the `platform`
**realm**, a **pluggable upstream IdP broker** (ADR-059), the per-app **OIDC clients**, the **Team group/role
taxonomy**, and the **upstream-group → Keycloak-group membership mappers**.

## Provisions

- `keycloak_realm` — the `platform` realm (issuer `<keycloak_url>/realms/platform`).
- **Pluggable upstream broker** (`var.upstream`, ADR-059) — exactly one of:
  - `keycloak_saml_identity_provider` (e.g. AWS Identity Center — NameID=Email, `principal_type=SUBJECT`,
    `trust_email`, `sync_mode=FORCE`), or
  - `keycloak_oidc_identity_provider` (e.g. Okta / Entra / Google).

  Plus a `keycloak_attribute_importer_identity_provider_mapper` that imports the upstream email (SAML
  `attribute_name` / OIDC `claim_name`) onto the Keycloak user. The `alias` is the stable downstream-facing seam;
  only this block changes per environment. **Presets:** [docs/runbooks/keycloak-upstream-idp.md](../../../docs/runbooks/keycloak-upstream-idp.md).
- **Per-app OIDC clients** (`var.clients`: ArgoCD, Backstage, oauth2-proxy) — each a confidential
  `keycloak_openid_client` with a `groups` claim mapper and a `roles` claim mapper, plus a generated secret
  stored in Secrets Manager at `platform/keycloak/<id>-oidc` (a Keycloak-specific path — no collision with Dex's
  `platform/<id>/oidc` during coexistence). Apps repoint at the B3/B4 cutover.
- **Team taxonomy** (`var.teams`, from the canonical `infra/live/aws/_teams.hcl`) — one `keycloak_group` per Team,
  plus the ADR-049 developer-access realm roles (`tenant-operate` for preprod, `tenant-view` for prod), assigned
  to each group by its envelope.
- **Membership mappers** (ADR-059) — one `keycloak_custom_identity_provider_mapper` (advanced-group) per Team:
  when a brokered login's group claim (`upstream.group_claim`) carries the team's `ssoGroup`, the user joins the
  Keycloak group `/<team>` and inherits its roles, populating both the `groups` and `roles` claims. **Inert**
  when the upstream emits no groups (`group_claim = ""`, e.g. AWS IdC).

## Usage

The **provider config** (url + admin creds) is injected by the unit's `generate` block (admin-cli password grant
against the bootstrap admin in Secrets Manager `platform/keycloak/admin`); the module declares only the
`keycloak` provider requirement. So the module **validates** standalone but is **applied** by the unit against a
live Keycloak.

```hcl
module "keycloak_config" {
  source       = "../../modules/keycloak-config"
  keycloak_url = "https://keycloak.aws.refplat.org"

  upstream = {
    alias       = "aws-sso"
    protocol    = "saml"
    group_claim = "" # AWS IdC emits no groups — membership mappers stay inert
    saml = {
      sso_url = var.keycloak_sso_url
      ca_data = var.keycloak_sso_ca_data # BARE base64 cert body — see the runbook
    }
  }
}
```

For Okta / Entra / Google (OIDC) `upstream` blocks — and the group-claim setup each needs — see
[docs/runbooks/keycloak-upstream-idp.md](../../../docs/runbooks/keycloak-upstream-idp.md).

## Prerequisite (manual, one-time)

For the SAML (AWS Identity Center) upstream: a dedicated Identity Center SAML application for Keycloak (its own
cert) → `keycloak_sso_url` / `keycloak_sso_ca_data` in `secrets.hcl`. See
[docs/runbooks/keycloak-sso.md](../../../docs/runbooks/keycloak-sso.md). **Cert format:** `saml.ca_data` is the
bare base64 cert body (no PEM headers), unlike Dex's.

## Testing

Validate-only in CI (the provider needs a live admin API). Verified during development by applying against an
ephemeral Keycloak (`docker run quay.io/keycloak/keycloak:26.6.3 start-dev`): both an **OIDC upstream** (IdP +
email importer + per-team advanced-group mappers create with the expected `extra_config`, re-plan is a clean
no-op) and the **SAML default** (`group_claim = ""` → zero group mappers; email importer on the `attribute.name`
path) — and the protocol switch destroys/recreates cleanly. Apply is rebuild-gated. The runtime brokered-login
membership assignment (and offboarding removal) needs a real login and is a rebuild-time check.

## Membership

The mappers above are the membership **mechanism**, but they only fire under a **group-emitting upstream**. With
AWS Identity Center (the current upstream) `group_claim = ""`, so the `groups`/`roles` claims are present but
empty for every user — the ArgoCD/Backstage cutovers (B3/B4) can authenticate but can't grant group-based access
until a group-emitting upstream (Okta/Entra/Google) is wired. This is an **IdC limitation, not a Keycloak one**
(ADR-059): any group-emitting upstream dissolves it with no downstream change.

## Not here (→ later)

Outbound **SCIM** (Keycloak→AWS in standalone mode, external SaaS — ADR-059 item 4); wiring a **live** upstream
tenant; the ArgoCD OIDC cutover (B3) + Backstage RBAC (#197, B4) that consume the claims; wiring the app
ExternalSecrets (the client secrets sit in Secrets Manager, unread); per-environment registry filtering; full
`teams.hcl` consolidation; the Dex→Keycloak issuer cutover.
