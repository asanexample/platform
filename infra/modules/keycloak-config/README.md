# keycloak-config

Configures a running **Keycloak** (deployed by the [`keycloak`](../keycloak/) module) via the official
`keycloak/keycloak` Terraform provider — the access-model-as-code (ADR-053). **B2, first slice:** the `platform`
**realm** + the Identity Center **SAML identity-provider broker** (`aws-sso`) + an email attribute mapper, so
Keycloak federates authentication up to AWS SSO.

Per-app OIDC clients and the Team→group/role taxonomy are later slices; ArgoCD/Backstage cutover is B3/B4.

## Provisions

- `keycloak_realm` — the `platform` realm (issuer `<keycloak_url>/realms/platform`).
- `keycloak_saml_identity_provider` `aws-sso` — the Identity Center broker (mirrors the Dex connector: IdC SSO
  URL + signing cert, NameID=Email, `principal_type=SUBJECT`, `trust_email`, `sync_mode=FORCE`).
- `keycloak_attribute_importer_identity_provider_mapper` — imports the SAML email onto the Keycloak user.
- **Per-app OIDC clients** (`var.clients`: ArgoCD, Backstage, oauth2-proxy) — confidential
  `keycloak_openid_client` + a `groups` claim mapper + a `roles` claim mapper each, with a generated secret
  stored in Secrets Manager at `platform/keycloak/<id>-oidc` (a Keycloak-specific path — no collision with Dex's
  `platform/<id>/oidc` during coexistence). Nothing consumes these yet; apps repoint at the B3/B4 cutover.
- **Team taxonomy** (`var.teams`, from the canonical `infra/live/aws/_teams.hcl`) — one `keycloak_group` per
  Team + the ADR-049 developer-access realm roles (`tenant-operate` for preprod, `tenant-view` for prod),
  assigned to each group by its envelope. The clients' `groups`/`roles` mappers carry these as named claims.

## Usage

The **provider config** (url + admin creds) is injected by the unit's `generate` block (admin-cli password
grant against the bootstrap admin in Secrets Manager `platform/keycloak/admin`); the module declares only the
`keycloak` provider requirement. So the module **validates** standalone but is **applied** by the unit against
a live Keycloak.

```hcl
module "keycloak_config" {
  source       = "../../modules/keycloak-config"
  keycloak_url = "https://keycloak.aws.refplat.org"
  saml_sso_url = var.keycloak_sso_url
  saml_ca_data = var.keycloak_sso_ca_data # BARE base64 cert body — see the runbook
}
```

## Prerequisite (manual, one-time)

A dedicated Identity Center SAML application for Keycloak (its own cert) → `keycloak_sso_url` /
`keycloak_sso_ca_data` in `secrets.hcl`. See [docs/runbooks/keycloak-sso.md](../../../docs/runbooks/keycloak-sso.md).
**Cert format:** `saml_ca_data` is the bare base64 cert body (no PEM headers), unlike Dex's.

## Testing

Validate-only in CI (the provider needs a live admin API). Verified during development by applying against an
ephemeral Keycloak (`docker run quay.io/keycloak/keycloak:26.6.3 start-dev`) — realm + broker + mapper create
cleanly and re-plan is idempotent. Apply is rebuild-gated.

## Membership (out of scope — a dependency for B3/B4)

The taxonomy defines groups/roles as code but does NOT assign *which users* are in each group (Identity Center
can't emit groups over SAML). Membership comes later via **SCIM** or manual assignment. Until then the
`groups`/`roles` claims are **empty for every user** — so the ArgoCD/Backstage cutovers (B3/B4) can authenticate
but cannot grant group-based access yet. Membership is a prerequisite for those cutovers delivering real authz.

## Not here (→ later)

Group **membership** (SCIM); the ArgoCD OIDC cutover (B3) + Backstage RBAC (#197, B4) that consume the claims;
wiring the app ExternalSecrets (the client secrets sit in Secrets Manager, unread); per-environment registry
filtering; full `teams.hcl` consolidation; the Dex→Keycloak issuer cutover.
