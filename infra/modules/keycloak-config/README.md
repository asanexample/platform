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
- **Public clients** (`var.public_clients`, e.g. `argocd-cli`) — PUBLIC `keycloak_openid_client` with PKCE S256,
  **no** secret / no Secrets Manager entry (for CLIs that can't safely hold a confidential secret), with the same
  `groups`/`roles` claim mappers.
- **Team taxonomy** (`var.teams`, from the canonical `infra/live/aws/_teams.hcl`) — one `keycloak_group` per Team,
  plus the ADR-049 developer-access realm roles (`tenant-operate` for preprod, `tenant-view` for prod), assigned
  to each group by its envelope.
- **Platform groups** (`var.platform_groups`, e.g. `platform-admins`) — non-team realm groups (no envelope/roles)
  emitted in the `groups` claim; apps map the name directly (e.g. ArgoCD `platform-admins` → org-admin). Get a
  membership mapper too when they declare an `ssoGroup`.
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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |
| <a name="requirement_keycloak"></a> [keycloak](#requirement\_keycloak) | ~> 5.7 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |
| <a name="provider_keycloak"></a> [keycloak](#provider\_keycloak) | ~> 5.7 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [keycloak_attribute_importer_identity_provider_mapper.email](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/attribute_importer_identity_provider_mapper) | resource |
| [keycloak_custom_identity_provider_mapper.platform_group](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/custom_identity_provider_mapper) | resource |
| [keycloak_custom_identity_provider_mapper.team_group](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/custom_identity_provider_mapper) | resource |
| [keycloak_group.platform](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/group) | resource |
| [keycloak_group.team](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/group) | resource |
| [keycloak_group_roles.team](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/group_roles) | resource |
| [keycloak_oidc_identity_provider.upstream](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/oidc_identity_provider) | resource |
| [keycloak_openid_client.public](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client) | resource |
| [keycloak_openid_client.this](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client) | resource |
| [keycloak_openid_group_membership_protocol_mapper.groups](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_group_membership_protocol_mapper) | resource |
| [keycloak_openid_group_membership_protocol_mapper.public_groups](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_group_membership_protocol_mapper) | resource |
| [keycloak_openid_user_realm_role_protocol_mapper.public_roles](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_user_realm_role_protocol_mapper) | resource |
| [keycloak_openid_user_realm_role_protocol_mapper.roles](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_user_realm_role_protocol_mapper) | resource |
| [keycloak_realm.this](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/realm) | resource |
| [keycloak_role.posture](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/role) | resource |
| [keycloak_saml_identity_provider.upstream](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/saml_identity_provider) | resource |
| [random_password.client](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_keycloak_url"></a> [keycloak\_url](#input\_keycloak\_url) | Base URL of the running Keycloak (e.g. https://keycloak.aws.refplat.org). Used to derive the realm issuer + the SP entity id. | `string` | n/a | yes |
| <a name="input_upstream"></a> [upstream](#input\_upstream) | The upstream IdP Keycloak brokers authentication to (ADR-059). `protocol` selects SAML (e.g. AWS Identity<br/>Center) or OIDC (Okta / Entra / Google); fill the matching sub-object. `group_claim` is the name of the group<br/>claim/attribute the upstream emits — set it (e.g. "groups") to drive the per-team membership mappers; ""<br/>(the default, and AWS IdC's reality) leaves them inert. The broker endpoint is<br/><keycloak\_url>/realms/<realm>/broker/<alias>/endpoint. | <pre>object({<br/>    alias           = optional(string, "aws-sso")<br/>    display_name    = optional(string, "AWS SSO")<br/>    protocol        = string # "saml" | "oidc"<br/>    group_claim     = optional(string, "")<br/>    email_attribute = optional(string, "email")<br/>    saml = optional(object({<br/>      sso_url                = string<br/>      ca_data                = string # BARE base64 cert body (no PEM headers); see docs/runbooks/keycloak-sso.md<br/>      entity_id              = optional(string, "")<br/>      name_id_format         = optional(string, "Email")<br/>      principal_type         = optional(string, "SUBJECT")<br/>      want_assertions_signed = optional(bool, true)<br/>    }), null)<br/>    oidc = optional(object({<br/>      authorization_url = string<br/>      token_url         = string<br/>      user_info_url     = optional(string, "")<br/>      jwks_url          = optional(string, "")<br/>      client_id         = string<br/>      default_scopes    = optional(string, "openid email profile groups")<br/>    }), null)<br/>  })</pre> | n/a | yes |
| <a name="input_clients"></a> [clients](#input\_clients) | OIDC clients to register in the realm. Each gets a confidential client + a `groups` claim mapper + a<br/>generated secret stored in Secrets Manager at platform/keycloak/<id>-oidc (a Keycloak-specific path, so it<br/>does NOT collide with Dex's platform/<id>/oidc during coexistence). Apps repoint to these at the B3/B4<br/>cutover. Add a client here to onboard another app. | <pre>map(object({<br/>    name          = string<br/>    redirect_uris = list(string)<br/>  }))</pre> | <pre>{<br/>  "argocd": {<br/>    "name": "ArgoCD",<br/>    "redirect_uris": [<br/>      "https://argocd.aws.refplat.org/auth/callback"<br/>    ]<br/>  },<br/>  "backstage": {<br/>    "name": "Backstage",<br/>    "redirect_uris": [<br/>      "https://backstage.aws.refplat.org/api/auth/oidc/handler/frame"<br/>    ]<br/>  },<br/>  "oauth2-proxy": {<br/>    "name": "OAuth2 Proxy (Backstage)",<br/>    "redirect_uris": [<br/>      "https://backstage.aws.refplat.org/oauth2/callback"<br/>    ]<br/>  }<br/>}</pre> | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to configure the realm + broker | `bool` | `true` | no |
| <a name="input_platform_groups"></a> [platform\_groups](#input\_platform\_groups) | Non-team platform realm groups (e.g. platform-admins, ADR-059), separate from teams: each gets a Keycloak<br/>group (emitted in the `groups` claim) and — when it carries an `ssoGroup` and the upstream emits groups — an<br/>advanced-group membership mapper. No tenant envelope/roles (apps match the group name directly). Empty<br/>ssoGroup leaves membership to a group-emitting upstream / manual assignment (claims stay empty under AWS IdC). | `map(object({ ssoGroup = optional(string, "") }))` | <pre>{<br/>  "platform-admins": {}<br/>}</pre> | no |
| <a name="input_public_clients"></a> [public\_clients](#input\_public\_clients) | PUBLIC OIDC clients (PKCE S256, NO client secret, no Secrets Manager entry) — for CLIs that can't safely hold<br/>a confidential secret (e.g. the ArgoCD CLI). Each gets the same `groups`/`roles` claim mappers as the<br/>confidential clients so CLI tokens carry the access-model claims. See ADR-059. | <pre>map(object({<br/>    name          = string<br/>    redirect_uris = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_realm_display_name"></a> [realm\_display\_name](#input\_realm\_display\_name) | Human-friendly realm name (login page). | `string` | `"Platform"` | no |
| <a name="input_realm_name"></a> [realm\_name](#input\_realm\_name) | Realm to create. Apps' OIDC issuer is <keycloak\_url>/realms/<realm\_name>. | `string` | `"platform"` | no |
| <a name="input_secret_recovery_window_days"></a> [secret\_recovery\_window\_days](#input\_secret\_recovery\_window\_days) | Secrets Manager recovery window for generated client secrets. 0 = force-delete (setup-friendly); raise for prod. | `number` | `0` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the generated Secrets Manager client secrets. | `map(string)` | `{}` | no |
| <a name="input_teams"></a> [teams](#input\_teams) | Canonical Team registry (from infra/live/aws/\_teams.hcl, ADR-049/053). Map of team name -> { ssoGroup,<br/>envelope{allowedEnvironments,...}, and canonical-only fields }. Generates one Keycloak group per team + the<br/>developer-access roles assigned by envelope. Type `any` to match the crossplane module's `var.teams`. Empty<br/>= no groups. NOTE: group MEMBERSHIP (which users) is out of scope (SCIM/manual) — claims stay empty until then. | `any` | `{}` | no |
| <a name="input_upstream_oidc_client_secret"></a> [upstream\_oidc\_client\_secret](#input\_upstream\_oidc\_client\_secret) | OIDC client secret for the upstream broker app (required when upstream.protocol = "oidc"; from secrets.hcl). Unused for SAML. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_broker_alias"></a> [broker\_alias](#output\_broker\_alias) | Alias of the upstream identity provider (broker). |
| <a name="output_broker_endpoint"></a> [broker\_endpoint](#output\_broker\_endpoint) | Broker callback endpoint — the upstream app's ACS (SAML) / redirect URI (OIDC) target. |
| <a name="output_broker_protocol"></a> [broker\_protocol](#output\_broker\_protocol) | Protocol of the upstream broker (saml \| oidc). |
| <a name="output_client_ids"></a> [client\_ids](#output\_client\_ids) | Registered confidential OIDC client IDs. |
| <a name="output_client_secret_names"></a> [client\_secret\_names](#output\_client\_secret\_names) | Secrets Manager secret names holding each client's secret (key: client-secret). Apps consume these at the B3/B4 cutover. |
| <a name="output_group_membership_mappers"></a> [group\_membership\_mappers](#output\_group\_membership\_mappers) | Teams whose upstream group is mapped to a Keycloak group (empty when the upstream emits no groups). |
| <a name="output_group_names"></a> [group\_names](#output\_group\_names) | Keycloak groups created from the Team registry (one per Team). |
| <a name="output_issuer"></a> [issuer](#output\_issuer) | OIDC issuer for apps in this realm (<keycloak\_url>/realms/<realm>). |
| <a name="output_platform_group_names"></a> [platform\_group\_names](#output\_platform\_group\_names) | Non-team platform groups (e.g. platform-admins). |
| <a name="output_public_client_ids"></a> [public\_client\_ids](#output\_public\_client\_ids) | Registered public (PKCE, no-secret) OIDC client IDs — e.g. CLI clients. |
| <a name="output_realm_id"></a> [realm\_id](#output\_realm\_id) | The realm id (= name). |
| <a name="output_realm_name"></a> [realm\_name](#output\_realm\_name) | The configured realm name. |
| <a name="output_realm_roles"></a> [realm\_roles](#output\_realm\_roles) | Developer-access realm roles. |
<!-- END_TF_DOCS -->