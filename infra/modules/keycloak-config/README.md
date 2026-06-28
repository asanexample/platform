# keycloak-config

Configures a running **Keycloak** (deployed by the [`keycloak`](../keycloak/) module) via the official
`keycloak/keycloak` Terraform provider — the access-model-as-code (ADR-053). By **default Keycloak is the IdP of
record** (ADR-059): identity lives in the `platform` realm — users seeded as code, placed into the Team/platform
groups, with the group→role→claim flow live and **no external dependency**. Federating a corporate IdP
(Okta/Entra/Google/AWS IdC) is an **optional** one-block swap (`var.upstream`) that changes nothing downstream.

It provisions the `platform` **realm**, the **seed users** (default identity source), the per-app **OIDC
clients**, the **Team group/role taxonomy**, and — only when federating — the **upstream IdP broker** + its
**group→Keycloak-group membership mappers**.

## Provisions

- `keycloak_realm` — the `platform` realm (issuer `<keycloak_url>/realms/platform`).
- **Seed users** (`var.users`, the default identity source) — a `keycloak_user` per entry placed exhaustively
  into its realm groups (`keycloak_user_groups`), so membership → roles → claims is live with no upstream. Each
  gets a **temporary, must-change** password generated into Secrets Manager at
  `platform/keycloak/seed-user/<username>` (never in git). Empty when federating instead.
- **Optional upstream broker** (`var.upstream`, ADR-059) — `null` by default (standalone). When set, exactly one
  of:
  - `keycloak_saml_identity_provider` (e.g. AWS Identity Center — NameID=Email, `principal_type=SUBJECT`,
    `trust_email`, `sync_mode=FORCE`), or
  - `keycloak_oidc_identity_provider` (e.g. Okta / Entra / Google).

  Plus a `keycloak_attribute_importer_identity_provider_mapper` that imports the upstream email (SAML
  `attribute_name` / OIDC `claim_name`) onto the Keycloak user. The `alias` is the stable downstream-facing seam;
  only this block changes per environment. **Presets:** [docs/runbooks/keycloak-upstream-idp.md](../../../docs/runbooks/keycloak-upstream-idp.md).
- **Per-app OIDC clients** (`var.clients`: ArgoCD, Backstage, Grafana) — each a confidential
  `keycloak_openid_client` with a `groups` claim mapper and a `roles` claim mapper, plus a generated secret
  stored in Secrets Manager at `platform/keycloak/<id>-oidc`. Each app consumes its client secret via an
  ExternalSecret.
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
- **Auth strength** (#885 / identity strategy §3.1) — when Keycloak is the IdP of record (`local.manage_mfa` =
  standalone), the factor lives here:
  - A custom **browser flow** (`platform-browser`) requires a **phishing-resistant passkey** (WebAuthn
    **passwordless**, `webauthn-authenticator-passwordless`) for **all** workforce — **no OTP anywhere** (OTP is
    phishable via an attacker-in-the-middle relay). Cookie / IdP-redirector short-circuits stay ALTERNATIVE; the
    `platform-forms` subflow is ALTERNATIVE so an SSO cookie isn't forced back through the password form.
  - **Forced enrollment:** `webauthn-register-passwordless` as a **default required action** (new users enroll a
    passkey at first login); the REQUIRED passwordless execution also force-enrolls anyone the default action
    missed, in-flow.
  - **Hardened recovery:** `reset_password_allowed = false` (`var.reset_password_allowed`) — recovery is a
    **backup passkey** or admin re-provision, never a phishable self-service reset.
  - Realm **WebAuthn passwordless policy** (RP id = the Keycloak host, user-verification + resident key
    required), consciously-set **session/access-token lifetimes** (`var.session`), a **password policy** for the
    seed accounts' first factor, **brute-force** defenses, and **login + admin event logging**
    (`keycloak_realm_events`, `var.auth_event_logging` — closes the audit-logging gap).
  - The **`acr.loa.map`** assurance vocabulary is set as the seam for **step-up at elevation** (the standing
    factor is here; the step-up *triggering* is layered by the temporary-power checkout, P3).
  - **Two-apply, no-lockout rollout** (Keycloak is Tier-0): everything above is created on apply-1, but the
    **binding** of the flow as the realm browser flow is gated behind **`var.enforce_browser_mfa`** (default
    `false`). Flip it `true` on apply-2 only **after** `admin` has enrolled a passkey; `admin-cli`'s master-realm
    direct-grant is the break-glass, independent of any browser flow. **Inert when federating** (the upstream
    owns the factor; assurance is honored across the seam). Master-realm admin hardening → **#899**.

## Usage

The **provider config** (url + admin creds) is injected by the unit's `generate` block (admin-cli password grant
against the bootstrap admin in Secrets Manager `platform/keycloak/admin`); the module declares only the
`keycloak` provider requirement. So the module **validates** standalone but is **applied** by the unit against a
live Keycloak.

**Default — Keycloak is the IdP of record** (no upstream; identity seeded as code):

```hcl
module "keycloak_config" {
  source       = "../../modules/keycloak-config"
  keycloak_url = "https://keycloak.aws.refplat.org"

  # upstream = null (omitted) — Keycloak owns identity. Seed users into the realm groups:
  users = {
    admin       = { email = "admin@example.com",     groups = ["platform-admins"] }
    "dev-alpha" = { email = "dev-alpha@example.com", groups = ["alpha"] }
  }
  teams = local.teams # one group + posture roles per team
}
```

**Optional — federate a corporate IdP** (e.g. AWS IdC over SAML; drop `users`, set `upstream`):

```hcl
  upstream = {
    alias       = "aws-sso"
    protocol    = "saml"
    group_claim = "" # AWS IdC emits no groups — membership mappers stay inert (use _teams.hcl/UI)
    saml = {
      sso_url = var.keycloak_sso_url
      ca_data = var.keycloak_sso_ca_data # BARE base64 cert body — see the runbook
    }
  }
```

For Okta / Entra / Google (OIDC) `upstream` blocks — and the group-claim setup each needs — see
[docs/runbooks/keycloak-upstream-idp.md](../../../docs/runbooks/keycloak-upstream-idp.md).

## Prerequisite (manual, one-time)

**None** in the default standalone mode. Only when **federating** a SAML upstream (e.g. AWS Identity Center) do
you need a dedicated SAML application for Keycloak (its own cert) → `keycloak_sso_url` / `keycloak_sso_ca_data` in
`secrets.hcl`; see [docs/runbooks/keycloak-upstream-idp.md](../../../docs/runbooks/keycloak-upstream-idp.md).
**Cert format:** `saml.ca_data` is the bare base64 cert body (no PEM headers), unlike Dex's.

## Testing

Validate-only in CI (the provider needs a live admin API). Verified during development by applying against an
ephemeral Keycloak (`docker run quay.io/keycloak/keycloak:26.6.3 start-dev`): both an **OIDC upstream** (IdP +
email importer + per-team advanced-group mappers create with the expected `extra_config`, re-plan is a clean
no-op) and the **SAML default** (`group_claim = ""` → zero group mappers; email importer on the `attribute.name`
path) — and the protocol switch destroys/recreates cleanly. Apply is rebuild-gated. The runtime brokered-login
membership assignment (and offboarding removal) needs a real login and is a rebuild-time check.

## Membership

Membership (which users are in which group, and so which `groups`/`roles` claims they carry) comes from one of
three sources depending on mode:

- **Default — standalone (Keycloak is the IdP of record):** the seeded `var.users` (+ the Keycloak admin UI for
  ad-hoc users). Membership is **local and immediate** — no upstream needed, no gap.
- **Federated, group-emitting upstream (Okta/Entra/Google):** the `keycloak_custom_identity_provider_mapper`
  advanced-group mappers — when a brokered login's group claim (`upstream.group_claim`) carries a team's
  `ssoGroup`, the user joins `/<team>` and inherits its roles. This is the enterprise membership mechanism.
- **Federated, AWS Identity Center:** IdC emits **no** group claims, so the mappers are inert — membership falls
  back to `_teams.hcl`/UI. This is an **IdC limitation, not a Keycloak one** (ADR-059), and is why IdC is an
  optional federation mode, not the default.

## Not here (→ later)

Outbound **SCIM** (Keycloak→AWS in standalone mode, external SaaS — ADR-059 item 4); wiring a **live** upstream
tenant; per-environment registry filtering; full `teams.hcl` consolidation.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_keycloak"></a> [keycloak](#requirement\_keycloak) | ~> 5.7 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |
| <a name="provider_aws.preprod"></a> [aws.preprod](#provider\_aws.preprod) | ~> 6.0 |
| <a name="provider_keycloak"></a> [keycloak](#provider\_keycloak) | ~> 5.7 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.client_preprod](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.directory_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.client](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.client_preprod](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.directory_sync](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.user](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [keycloak_attribute_importer_identity_provider_mapper.email](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/attribute_importer_identity_provider_mapper) | resource |
| [keycloak_attribute_importer_identity_provider_mapper.github_login](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/attribute_importer_identity_provider_mapper) | resource |
| [keycloak_attribute_importer_identity_provider_mapper.slack_userid](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/attribute_importer_identity_provider_mapper) | resource |
| [keycloak_authentication_bindings.master](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_bindings) | resource |
| [keycloak_authentication_bindings.this](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_bindings) | resource |
| [keycloak_authentication_execution.browser_cookie](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.browser_idp](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.forms_userpass](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.master_cookie](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.master_idp](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.master_mfa_webauthn](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.master_userpass](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_execution.mfa_webauthn](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_execution) | resource |
| [keycloak_authentication_flow.browser](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_flow) | resource |
| [keycloak_authentication_flow.master_browser](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_flow) | resource |
| [keycloak_authentication_subflow.browser_forms](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_subflow) | resource |
| [keycloak_authentication_subflow.browser_mfa](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_subflow) | resource |
| [keycloak_authentication_subflow.master_forms](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_subflow) | resource |
| [keycloak_authentication_subflow.master_mfa](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/authentication_subflow) | resource |
| [keycloak_custom_identity_provider_mapper.platform_group](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/custom_identity_provider_mapper) | resource |
| [keycloak_custom_identity_provider_mapper.team_group](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/custom_identity_provider_mapper) | resource |
| [keycloak_group.platform](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/group) | resource |
| [keycloak_group.team](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/group) | resource |
| [keycloak_group_roles.team](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/group_roles) | resource |
| [keycloak_oidc_identity_provider.github](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/oidc_identity_provider) | resource |
| [keycloak_oidc_identity_provider.slack](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/oidc_identity_provider) | resource |
| [keycloak_oidc_identity_provider.upstream](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/oidc_identity_provider) | resource |
| [keycloak_openid_client.directory_sync](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client) | resource |
| [keycloak_openid_client.public](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client) | resource |
| [keycloak_openid_client.this](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client) | resource |
| [keycloak_openid_client_default_scopes.confidential](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client_default_scopes) | resource |
| [keycloak_openid_client_default_scopes.public](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client_default_scopes) | resource |
| [keycloak_openid_client_scope.groups](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client_scope) | resource |
| [keycloak_openid_client_service_account_role.directory_sync_view_users](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_client_service_account_role) | resource |
| [keycloak_openid_group_membership_protocol_mapper.groups](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_group_membership_protocol_mapper) | resource |
| [keycloak_openid_user_realm_role_protocol_mapper.public_roles](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_user_realm_role_protocol_mapper) | resource |
| [keycloak_openid_user_realm_role_protocol_mapper.roles](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/openid_user_realm_role_protocol_mapper) | resource |
| [keycloak_realm.this](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/realm) | resource |
| [keycloak_realm_events.this](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/realm_events) | resource |
| [keycloak_required_action.master_webauthn_register_passwordless](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/required_action) | resource |
| [keycloak_required_action.webauthn_register_passwordless](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/required_action) | resource |
| [keycloak_role.posture](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/role) | resource |
| [keycloak_saml_identity_provider.upstream](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/saml_identity_provider) | resource |
| [keycloak_user.seed](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/user) | resource |
| [keycloak_user_groups.seed](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/resources/user_groups) | resource |
| [random_password.client](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.directory_sync](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.user](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_secretsmanager_secret_version.github_idp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret_version) | data source |
| [aws_secretsmanager_secret_version.slack_idp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/secretsmanager_secret_version) | data source |
| [keycloak_openid_client.realm_management](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs/data-sources/openid_client) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_keycloak_url"></a> [keycloak\_url](#input\_keycloak\_url) | Base URL of the running Keycloak (e.g. https://keycloak.aws.refplat.org). Used to derive the realm issuer + the SP entity id. | `string` | n/a | yes |
| <a name="input_auth_event_logging"></a> [auth\_event\_logging](#input\_auth\_event\_logging) | Enable Keycloak login + admin event logging (keycloak\_realm\_events) — the audit trail for the realm (#885; closes the "audit-logging off" gap). Listener defaults to jboss-logging so events land in the pod logs → Loki. | `bool` | `true` | no |
| <a name="input_brute_force_protection"></a> [brute\_force\_protection](#input\_brute\_force\_protection) | Realm brute-force detection settings (security\_defenses). Enabled by default; tune max\_login\_failures / lockout behavior here. | <pre>object({<br/>    enabled            = optional(bool, true)<br/>    max_login_failures = optional(number, 10)<br/>    permanent_lockout  = optional(bool, false)<br/>  })</pre> | `{}` | no |
| <a name="input_clients"></a> [clients](#input\_clients) | OIDC clients to register in the realm. Each gets a confidential client + a `groups` claim mapper + a<br/>generated secret stored in Secrets Manager at platform/keycloak/<id>-oidc. Each app consumes its client<br/>secret via an ExternalSecret. Add a client here to onboard another app. | <pre>map(object({<br/>    name          = string<br/>    redirect_uris = list(string)<br/>    # Allowed post-logout redirect URIs (RP-initiated OIDC logout). Empty -> "+" (inherit redirect_uris).<br/>    post_logout_redirect_uris = optional(list(string), [])<br/>  }))</pre> | <pre>{<br/>  "argocd": {<br/>    "name": "ArgoCD",<br/>    "post_logout_redirect_uris": [<br/>      "https://argocd.aws.refplat.org/*"<br/>    ],<br/>    "redirect_uris": [<br/>      "https://argocd.aws.refplat.org/auth/callback"<br/>    ]<br/>  },<br/>  "backstage": {<br/>    "name": "Backstage",<br/>    "post_logout_redirect_uris": [<br/>      "https://backstage.aws.refplat.org/*"<br/>    ],<br/>    "redirect_uris": [<br/>      "https://backstage.aws.refplat.org/api/auth/oidc/handler/frame"<br/>    ]<br/>  },<br/>  "grafana": {<br/>    "name": "Grafana",<br/>    "post_logout_redirect_uris": [<br/>      "https://grafana.aws.refplat.org/*"<br/>    ],<br/>    "redirect_uris": [<br/>      "https://grafana.aws.refplat.org/login/generic_oauth"<br/>    ]<br/>  },<br/>  "rollouts": {<br/>    "name": "Argo Rollouts",<br/>    "post_logout_redirect_uris": [<br/>      "https://rollouts.aws.refplat.org/*",<br/>      "https://rollouts.preprod.aws.refplat.org/*"<br/>    ],<br/>    "redirect_uris": [<br/>      "https://rollouts.aws.refplat.org/oauth2/callback",<br/>      "https://rollouts.preprod.aws.refplat.org/oauth2/callback"<br/>    ]<br/>  }<br/>}</pre> | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to configure the realm + broker | `bool` | `true` | no |
| <a name="input_enable_account_linking"></a> [enable\_account\_linking](#input\_enable\_account\_linking) | ADR-084 Phase 1: broker GitHub + Slack as LINKABLE identity providers (+ attribute mappers projecting<br/>githubLogin / slackUserId onto users) and create the read-only `directory-sync` service account. The two IdP<br/>app secrets are read from Secrets Manager (platform/keycloak/{github,slack}-idp); the directory-sync client<br/>secret is generated and published to platform/keycloak/directory-sync for the triage agent. | `bool` | `false` | no |
| <a name="input_enforce_browser_mfa"></a> [enforce\_browser\_mfa](#input\_enforce\_browser\_mfa) | Gates the BINDING of the custom passkey browser flow as the realm's browser flow — the apply-2 flip of the<br/>two-apply, no-lockout rollout (#885). FALSE (default = apply-1): the flow, the WebAuthn-register-passwordless<br/>default action, and the realm hardening are all created, but the built-in browser flow stays live so nobody<br/>is locked out before enrolling a passkey. TRUE (apply-2): bind the new flow — enrolled users log in by<br/>passkey, new users are force-enrolled. Keycloak is Tier-0, so flip this only AFTER `admin` has enrolled a<br/>passkey (+ a backup) via the Account Console. `admin-cli` master-realm direct-grant is the break-glass — it's<br/>independent of any browser flow, so a bad flow never locks out Terraform. | `bool` | `false` | no |
| <a name="input_enforce_master_browser_mfa"></a> [enforce\_master\_browser\_mfa](#input\_enforce\_master\_browser\_mfa) | Gates the BINDING of the master-realm passkey browser flow — the apply-2 flip of the master two-apply rollout<br/>(#899). Requires manage\_master\_admin. FALSE (default = apply-1): the master flow is built but the built-in<br/>master browser flow stays live (console not locked out). TRUE (apply-2): bind it — flip ONLY after a passkey<br/>is enrolled on the master `admin`. admin-cli direct-grant is unaffected either way (Terraform never locks out). | `bool` | `false` | no |
| <a name="input_manage_master_admin"></a> [manage\_master\_admin](#input\_manage\_master\_admin) | Opt-in master-realm admin-plane hardening (#899, ADR-087): build the passkey browser flow + the<br/>WebAuthn-register-passwordless default action on the MASTER realm (realm\_id = "master"), closing the<br/>human-console MFA bypass. Off by default. Does NOT touch admin-cli's direct-grant (the bootstrap +<br/>break-glass path — INVARIANT: never disabled). The master realm's keycloak\_realm object stays unmanaged;<br/>these resources rely on master's default WebAuthn policy. The full service-account provider migration is<br/>deliberately deferred (ADR-087). Pairs with enforce\_master\_browser\_mfa for the two-apply bind. | `bool` | `false` | no |
| <a name="input_password_policy"></a> [password\_policy](#input\_password\_policy) | Keycloak realm password policy string for local (seed/IdP-of-record) accounts. Empty disables it (e.g. when federating, where the upstream owns credentials). | `string` | `"length(14) and notUsername(undefined) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1) and passwordHistory(3)"` | no |
| <a name="input_platform_groups"></a> [platform\_groups](#input\_platform\_groups) | Non-team platform realm groups (e.g. platform-admins, ADR-059), separate from teams: each gets a Keycloak<br/>group (emitted in the `groups` claim) and — when it carries an `ssoGroup` and the upstream emits groups — an<br/>advanced-group membership mapper. No tenant envelope/roles (apps match the group name directly). Empty<br/>ssoGroup leaves membership to a group-emitting upstream / manual assignment (claims stay empty under AWS IdC). | `map(object({ ssoGroup = optional(string, "") }))` | <pre>{<br/>  "platform-admins": {}<br/>}</pre> | no |
| <a name="input_public_clients"></a> [public\_clients](#input\_public\_clients) | PUBLIC OIDC clients (PKCE S256, NO client secret, no Secrets Manager entry) — for CLIs that can't safely hold<br/>a confidential secret (e.g. the ArgoCD CLI). Each gets the same `groups`/`roles` claim mappers as the<br/>confidential clients so CLI tokens carry the access-model claims. See ADR-059. | <pre>map(object({<br/>    name          = string<br/>    redirect_uris = list(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_realm_display_name"></a> [realm\_display\_name](#input\_realm\_display\_name) | Human-friendly realm name (login page). | `string` | `"Platform"` | no |
| <a name="input_realm_name"></a> [realm\_name](#input\_realm\_name) | Realm to create. Apps' OIDC issuer is <keycloak\_url>/realms/<realm\_name>. | `string` | `"platform"` | no |
| <a name="input_replicate_client_secrets_to_preprod"></a> [replicate\_client\_secrets\_to\_preprod](#input\_replicate\_client\_secrets\_to\_preprod) | Client ids whose generated OIDC secret is ALSO written to the preprod account's Secrets Manager (via the<br/>aws.preprod provider), under the same name `platform/keycloak/<id>-oidc`. Lets a SPOKE cluster's ESO read the<br/>shared client secret locally (no cross-account KMS) to front a no-native-auth UI there with oauth2-proxy —<br/>e.g. `["rollouts"]` for the preprod Argo Rollouts dashboard. The Keycloak client is shared; only its secret<br/>is replicated. Empty = no replica. | `list(string)` | `[]` | no |
| <a name="input_reset_password_allowed"></a> [reset\_password\_allowed](#input\_reset\_password\_allowed) | Self-service "Forgot password". OFF by default (#885): passkeys are the factor, so recovery is a backup passkey or admin re-provision — a self-service reset would be a phishable backdoor. | `bool` | `false` | no |
| <a name="input_secret_recovery_window_days"></a> [secret\_recovery\_window\_days](#input\_secret\_recovery\_window\_days) | Secrets Manager recovery window for generated client secrets. 0 = force-delete (setup-friendly); raise for prod. | `number` | `0` | no |
| <a name="input_session"></a> [session](#input\_session) | Realm session + access-token lifetimes (Go duration strings) — consciously set to limit stolen-token blast<br/>radius (§3.1 "session lifetime is a tuned dial"). Keep sso\_idle\_timeout >= the apps' silent-refresh need<br/>(Backstage relies on Keycloak refresh tokens). The truly role-scoped AWS *console* lifetime (per-permission-<br/>set session\_duration) is owned by the Identity Center generator (#888); these govern the Keycloak/app side. | <pre>object({<br/>    sso_idle_timeout      = optional(string, "30m")<br/>    sso_max_lifespan      = optional(string, "10h")<br/>    access_token_lifespan = optional(string, "5m")<br/>  })</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the generated Secrets Manager client secrets. | `map(string)` | `{}` | no |
| <a name="input_teams"></a> [teams](#input\_teams) | Canonical Team registry (from infra/live/aws/\_teams.hcl, ADR-049/053). Map of team name -> { ssoGroup,<br/>envelope{allowedEnvironments,...}, and canonical-only fields }. Generates one Keycloak group per team + the<br/>developer-access roles assigned by envelope. Type `any` to match the crossplane module's `var.teams`. Empty<br/>= no groups. NOTE: group MEMBERSHIP (which users) is out of scope (SCIM/manual) — claims stay empty until then. | `any` | `{}` | no |
| <a name="input_upstream"></a> [upstream](#input\_upstream) | OPTIONAL upstream IdP to federate to (ADR-059). `null` (the DEFAULT) makes Keycloak the IdP of record —<br/>identity lives in this realm (see `users`), nothing brokers up, fully self-contained. Set this object to<br/>federate instead: `protocol` selects SAML (e.g. AWS Identity Center) or OIDC (Okta / Entra / Google); fill the<br/>matching sub-object. `group_claim` is the group claim/attribute the upstream emits — set it (e.g. "groups") to<br/>drive the per-team membership mappers; "" leaves them inert (AWS IdC's reality). Nothing DOWNSTREAM of the<br/>realm changes when this swaps — apps, claims, and the access model are invariant. Broker endpoint:<br/><keycloak\_url>/realms/<realm>/broker/<alias>/endpoint. | <pre>object({<br/>    alias           = optional(string, "aws-sso")<br/>    display_name    = optional(string, "AWS SSO")<br/>    protocol        = string # "saml" | "oidc"<br/>    group_claim     = optional(string, "")<br/>    email_attribute = optional(string, "email")<br/>    saml = optional(object({<br/>      sso_url                = string<br/>      ca_data                = string # BARE base64 cert body (no PEM headers); see docs/runbooks/keycloak-sso.md<br/>      entity_id              = optional(string, "")<br/>      name_id_format         = optional(string, "Email")<br/>      principal_type         = optional(string, "SUBJECT")<br/>      want_assertions_signed = optional(bool, true)<br/>    }), null)<br/>    oidc = optional(object({<br/>      authorization_url = string<br/>      token_url         = string<br/>      user_info_url     = optional(string, "")<br/>      jwks_url          = optional(string, "")<br/>      client_id         = string<br/>      default_scopes    = optional(string, "openid email profile groups")<br/>    }), null)<br/>  })</pre> | `null` | no |
| <a name="input_upstream_oidc_client_secret"></a> [upstream\_oidc\_client\_secret](#input\_upstream\_oidc\_client\_secret) | OIDC client secret for the upstream broker app (required when upstream.protocol = "oidc"; from secrets.hcl). Unused for SAML. | `string` | `""` | no |
| <a name="input_users"></a> [users](#input\_users) | Realm users seeded as code — the membership source when Keycloak is the IdP of record (upstream = null).<br/>Map of username -> { email, first\_name, last\_name, groups }. `groups` are realm group names (team groups<br/>from `teams`, e.g. "alpha", or platform groups, e.g. "platform-admins"); membership drives the group→role→<br/>claim flow directly (no upstream needed). Each user gets a TEMPORARY (must-change-on-first-login) password<br/>generated into Secrets Manager at platform/keycloak/seed-user/<username>. Empty (default) = no seeded users —<br/>use this with a federated `upstream` instead, where membership flows from the upstream group claim. | <pre>map(object({<br/>    email      = string<br/>    first_name = optional(string, "")<br/>    last_name  = optional(string, "")<br/>    groups     = optional(list(string), [])<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_auth_strength"></a> [auth\_strength](#output\_auth\_strength) | Auth-strength posture (#885): whether the passkey browser flow is built (standalone realm) and whether it's bound as the realm browser flow (the apply-2 enforce\_browser\_mfa flip). |
| <a name="output_broker_alias"></a> [broker\_alias](#output\_broker\_alias) | Alias of the upstream identity provider, or null when Keycloak is the IdP of record (no federation). |
| <a name="output_broker_endpoint"></a> [broker\_endpoint](#output\_broker\_endpoint) | Broker callback endpoint — the upstream app's ACS (SAML) / redirect URI (OIDC) target. Null when standalone. |
| <a name="output_broker_protocol"></a> [broker\_protocol](#output\_broker\_protocol) | Protocol of the upstream broker (saml \| oidc), or null when standalone. |
| <a name="output_client_ids"></a> [client\_ids](#output\_client\_ids) | Registered confidential OIDC client IDs. |
| <a name="output_client_secret_names"></a> [client\_secret\_names](#output\_client\_secret\_names) | Secrets Manager secret names holding each client's secret (key: client-secret). Each app consumes its secret via an ExternalSecret. |
| <a name="output_group_membership_mappers"></a> [group\_membership\_mappers](#output\_group\_membership\_mappers) | Teams whose upstream group is mapped to a Keycloak group (empty when the upstream emits no groups). |
| <a name="output_group_names"></a> [group\_names](#output\_group\_names) | Keycloak groups created from the Team registry (one per Team). |
| <a name="output_identity_source"></a> [identity\_source](#output\_identity\_source) | Where identity comes from: "keycloak" (IdP of record, standalone) or the federated broker protocol ("saml" \| "oidc"). |
| <a name="output_issuer"></a> [issuer](#output\_issuer) | OIDC issuer for apps in this realm (<keycloak\_url>/realms/<realm>). |
| <a name="output_platform_group_names"></a> [platform\_group\_names](#output\_platform\_group\_names) | Non-team platform groups (e.g. platform-admins). |
| <a name="output_public_client_ids"></a> [public\_client\_ids](#output\_public\_client\_ids) | Registered public (PKCE, no-secret) OIDC client IDs — e.g. CLI clients. |
| <a name="output_realm_id"></a> [realm\_id](#output\_realm\_id) | The realm id (= name). |
| <a name="output_realm_name"></a> [realm\_name](#output\_realm\_name) | The configured realm name. |
| <a name="output_realm_roles"></a> [realm\_roles](#output\_realm\_roles) | Developer-access realm roles. |
| <a name="output_seed_user_secret_names"></a> [seed\_user\_secret\_names](#output\_seed\_user\_secret\_names) | Secrets Manager names holding each seeded user's temporary password (standalone IdP mode). |
<!-- END_TF_DOCS -->