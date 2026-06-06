# Keycloak upstream IdP — presets (SAML / OIDC)

Keycloak is the platform's stable **identity seam** (ADR-059): everything downstream of it — the OIDC apps, AWS
access, the access-as-code generators — is invariant, and only the **upstream IdP** changes per environment. The
`keycloak-config` module's `var.upstream` selects that upstream. This runbook holds copy-paste presets.

The key payoff is **membership**: when the upstream emits a group claim, the per-team membership mappers bind
each team's `ssoGroup` (from `infra/live/aws/_teams.hcl`) to the Keycloak group `/<team>`, so a brokered user
joins the group at login and inherits its roles — populating the `groups` and `roles` claims apps consume. Set
`upstream.group_claim` to enable this; leave it `""` to keep the mappers inert.

> **Why AWS Identity Center is the weak case:** IdC can't emit group claims over SAML and is a poor SCIM source,
> so under IdC `group_claim = ""` and membership stays empty (ADR-059 "scenario C"). Any group-emitting upstream
> (Okta / Entra / Google's caveat below) dissolves this with **no downstream change**.

## AWS Identity Center (SAML) — the current default

Login-only (no group claim). One-time IdC SAML app setup: [keycloak-sso.md](keycloak-sso.md).

```hcl
upstream = {
  alias       = "aws-sso"
  display_name = "AWS SSO"
  protocol    = "saml"
  group_claim = "" # IdC emits no groups — membership mappers inert
  saml = {
    sso_url = var.keycloak_sso_url      # secrets.hcl
    ca_data = var.keycloak_sso_ca_data  # BARE base64 cert body (no PEM headers)
  }
}
```

## Okta (OIDC)

In Okta: create an **OIDC web app**, set the redirect URI to the broker endpoint
(`https://keycloak.aws.refplat.org/realms/platform/broker/okta/endpoint`), and add a **Groups claim** to the
ID token (name `groups`, filter `Matches regex .*`) plus the `groups` scope. `ssoGroup` in `_teams.hcl` is the
Okta **group name**.

```hcl
upstream = {
  alias       = "okta"
  display_name = "Okta"
  protocol    = "oidc"
  group_claim = "groups"
  oidc = {
    authorization_url = "https://{domain}.okta.com/oauth2/v1/authorize"
    token_url         = "https://{domain}.okta.com/oauth2/v1/token"
    user_info_url     = "https://{domain}.okta.com/oauth2/v1/userinfo"
    jwks_url          = "https://{domain}.okta.com/oauth2/v1/keys"
    client_id         = "0oa…"
  }
}
# + upstream_oidc_client_secret in secrets.hcl
```

## Microsoft Entra ID (OIDC)

In Entra: register an **app**, add the broker endpoint as a redirect URI, and under **Token configuration** add
the **groups claim**. Note Entra emits group **object-IDs** by default — so `ssoGroup` must be the group **OID**
(or configure Entra to emit `sAMAccountName`/display names for on-prem-synced groups, and use that). `{tenant}`
is the directory (tenant) ID.

```hcl
upstream = {
  alias       = "entra"
  display_name = "Microsoft Entra ID"
  protocol    = "oidc"
  group_claim = "groups"
  oidc = {
    authorization_url = "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize"
    token_url         = "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
    user_info_url     = "https://graph.microsoft.com/oidc/userinfo"
    jwks_url          = "https://login.microsoftonline.com/{tenant}/discovery/v2.0/keys"
    client_id         = "…"
  }
}
# + upstream_oidc_client_secret in secrets.hcl; ssoGroup = the group OBJECT-ID
```

## Google Workspace (OIDC)

Login works, but **Google does not put group membership in the ID token** (it's behind the Directory/Cloud
Identity API) — so this is the same class of gap as AWS IdC. Use `group_claim = ""` (membership inert) until a
group source is wired.

```hcl
upstream = {
  alias       = "google"
  display_name = "Google"
  protocol    = "oidc"
  group_claim = "" # no group claim in Google's ID token
  oidc = {
    authorization_url = "https://accounts.google.com/o/oauth2/v2/auth"
    token_url         = "https://oauth2.googleapis.com/token"
    user_info_url     = "https://openidconnect.googleapis.com/v1/userinfo"
    jwks_url          = "https://www.googleapis.com/oauth2/v3/certs"
    client_id         = "….apps.googleusercontent.com"
  }
}
# + upstream_oidc_client_secret in secrets.hcl
```

## Notes

- **Tip:** Keycloak's admin console can import an OIDC provider's endpoints from its discovery URL
  (`https://…/.well-known/openid-configuration`) once, to capture the four URLs for a preset.
- **Offboarding:** the membership mappers use `sync_mode = FORCE`, re-evaluated each login — a user dropped from
  the upstream group loses the Keycloak group on next login. Full deprovisioning of a user who stops logging in
  entirely is the **SCIM** story (ADR-059 item 4, deferred).
- **Apply is rebuild-gated.** Changing `upstream` is applied by the `keycloak-config` unit against the live
  Keycloak admin API; it is not CI-plan-tested (the provider needs a live API).
- **App consumers (B3+):** apps authorize from these claims. ArgoCD (B3, ADR-053/059) brokers via the `argocd`
  OIDC client, maps team groups → team-scoped AppProject roles and `platform-admins` → org-admin, and uses the
  public `argocd-cli` client for CLI login. Until membership is populated (a group-emitting upstream / SCIM) the
  claims are empty, so ArgoCD admin is via the local break-glass account.
