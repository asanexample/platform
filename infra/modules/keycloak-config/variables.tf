variable "create" {
  description = "Whether to configure the realm + broker"
  type        = bool
  default     = true
}

variable "keycloak_url" {
  description = "Base URL of the running Keycloak (e.g. https://keycloak.aws.refplat.org). Used to derive the realm issuer + the SP entity id."
  type        = string
}

variable "realm_name" {
  description = "Realm to create. Apps' OIDC issuer is <keycloak_url>/realms/<realm_name>."
  type        = string
  default     = "platform"
}

variable "realm_display_name" {
  description = "Human-friendly realm name (login page)."
  type        = string
  default     = "Platform"
}

# ---------------------------------------------------------------------------
# Upstream identity provider — the broker Keycloak federates authentication UP to.
# Pluggable per ADR-059: SAML (AWS Identity Center today) or OIDC (Okta / Entra / Google). Everything downstream
# of Keycloak is invariant; only this block changes per environment. Presets: docs/runbooks/keycloak-upstream-idp.md
# ---------------------------------------------------------------------------

variable "upstream" {
  description = <<-DESC
    OPTIONAL upstream IdP to federate to (ADR-059). `null` (the DEFAULT) makes Keycloak the IdP of record —
    identity lives in this realm (see `users`), nothing brokers up, fully self-contained. Set this object to
    federate instead: `protocol` selects SAML (e.g. AWS Identity Center) or OIDC (Okta / Entra / Google); fill the
    matching sub-object. `group_claim` is the group claim/attribute the upstream emits — set it (e.g. "groups") to
    drive the per-team membership mappers; "" leaves them inert (AWS IdC's reality). Nothing DOWNSTREAM of the
    realm changes when this swaps — apps, claims, and the access model are invariant. Broker endpoint:
    <keycloak_url>/realms/<realm>/broker/<alias>/endpoint.
  DESC
  default     = null
  type = object({
    alias           = optional(string, "aws-sso")
    display_name    = optional(string, "AWS SSO")
    protocol        = string # "saml" | "oidc"
    group_claim     = optional(string, "")
    email_attribute = optional(string, "email")
    saml = optional(object({
      sso_url                = string
      ca_data                = string # BARE base64 cert body (no PEM headers); see docs/runbooks/keycloak-sso.md
      entity_id              = optional(string, "")
      name_id_format         = optional(string, "Email")
      principal_type         = optional(string, "SUBJECT")
      want_assertions_signed = optional(bool, true)
    }), null)
    oidc = optional(object({
      authorization_url = string
      token_url         = string
      user_info_url     = optional(string, "")
      jwks_url          = optional(string, "")
      client_id         = string
      default_scopes    = optional(string, "openid email profile groups")
    }), null)
  })

  # All validations are null-safe — they only apply when federation is configured (upstream != null).
  validation {
    condition     = var.upstream == null || contains(["saml", "oidc"], var.upstream.protocol)
    error_message = "upstream.protocol must be \"saml\" or \"oidc\"."
  }
  validation {
    condition     = var.upstream == null || var.upstream.protocol != "saml" || var.upstream.saml != null
    error_message = "upstream.saml must be set when protocol = \"saml\"."
  }
  validation {
    condition     = var.upstream == null || var.upstream.protocol != "oidc" || var.upstream.oidc != null
    error_message = "upstream.oidc must be set when protocol = \"oidc\"."
  }
  validation {
    condition     = var.upstream == null || var.upstream.protocol != "oidc" || var.upstream_oidc_client_secret != ""
    error_message = "upstream_oidc_client_secret must be set when protocol = \"oidc\"."
  }
}

variable "upstream_oidc_client_secret" {
  description = "OIDC client secret for the upstream broker app (required when upstream.protocol = \"oidc\"; from secrets.hcl). Unused for SAML."
  type        = string
  sensitive   = true
  default     = ""
}

variable "users" {
  description = <<-DESC
    Realm users seeded as code — the membership source when Keycloak is the IdP of record (upstream = null).
    Map of username -> { email, first_name, last_name, groups }. `groups` are realm group names (team groups
    from `teams`, e.g. "alpha", or platform groups, e.g. "platform-admins"); membership drives the group→role→
    claim flow directly (no upstream needed). Each user gets a TEMPORARY (must-change-on-first-login) password
    generated into Secrets Manager at platform/keycloak/seed-user/<username>. Empty (default) = no seeded users —
    use this with a federated `upstream` instead, where membership flows from the upstream group claim.
  DESC
  type = map(object({
    email      = string
    first_name = optional(string, "")
    last_name  = optional(string, "")
    groups     = optional(list(string), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Per-app OIDC clients
# ---------------------------------------------------------------------------

variable "clients" {
  description = <<-DESC
    OIDC clients to register in the realm. Each gets a confidential client + a `groups` claim mapper + a
    generated secret stored in Secrets Manager at platform/keycloak/<id>-oidc. Each app consumes its client
    secret via an ExternalSecret. Add a client here to onboard another app.
  DESC
  type = map(object({
    name          = string
    redirect_uris = list(string)
    # Allowed post-logout redirect URIs (RP-initiated OIDC logout). Empty -> "+" (inherit redirect_uris).
    post_logout_redirect_uris = optional(list(string), [])
  }))
  default = {
    argocd = {
      name = "ArgoCD"
      # Browser flow only — the ArgoCD CLI (localhost) uses the PUBLIC argocd-cli client (var.public_clients).
      redirect_uris = ["https://argocd.aws.refplat.org/auth/callback"]
      # RP-initiated logout: ArgoCD's logout redirects here via Keycloak's end-session endpoint (so logging out
      # of ArgoCD also ends the Keycloak SSO session, not just the local ArgoCD session).
      post_logout_redirect_uris = ["https://argocd.aws.refplat.org/*"]
    }
    backstage = {
      name          = "Backstage"
      redirect_uris = ["https://backstage.aws.refplat.org/api/auth/oidc/handler/frame"]
      # RP-initiated logout: the Backstage sidebar "Sign out" redirects here via Keycloak's end-session
      # endpoint so logging out of Backstage also ends the Keycloak SSO session (not just the local Backstage
      # session). Mirrors argocd above. See packages/app/src/modules/auth in the asanexample/backstage repo.
      post_logout_redirect_uris = ["https://backstage.aws.refplat.org/*"]
    }
    grafana = {
      name = "Grafana"
      # Grafana's generic_oauth callback. The `groups` claim drives Grafana's role mapping (#592).
      redirect_uris = ["https://grafana.aws.refplat.org/login/generic_oauth"]
      # RP-initiated logout: signing out of Grafana also ends the Keycloak SSO session. Mirrors argocd/backstage.
      post_logout_redirect_uris = ["https://grafana.aws.refplat.org/*"]
    }
    rollouts = {
      name = "Argo Rollouts"
      # The Rollouts UI has no native auth, so an oauth2-proxy fronts it (infra/modules/oauth2-proxy); this is its
      # callback. Both clusters' hosts (platform hub + preprod spoke), each behind its own gateway.
      redirect_uris = [
        "https://rollouts.aws.refplat.org/oauth2/callback",
        "https://rollouts.preprod.aws.refplat.org/oauth2/callback",
      ]
      post_logout_redirect_uris = ["https://rollouts.aws.refplat.org/*", "https://rollouts.preprod.aws.refplat.org/*"]
    }
  }
}

variable "public_clients" {
  description = <<-DESC
    PUBLIC OIDC clients (PKCE S256, NO client secret, no Secrets Manager entry) — for CLIs that can't safely hold
    a confidential secret (e.g. the ArgoCD CLI). Each gets the same `groups`/`roles` claim mappers as the
    confidential clients so CLI tokens carry the access-model claims. See ADR-059.
  DESC
  type = map(object({
    name          = string
    redirect_uris = list(string)
  }))
  default = {}
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for generated client secrets. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
}

variable "enable_account_linking" {
  description = <<-DESC
    ADR-084 Phase 1: broker GitHub + Slack as LINKABLE identity providers (+ attribute mappers projecting
    githubLogin / slackUserId onto users) and create the read-only `directory-sync` service account. The two IdP
    app secrets are read from Secrets Manager (platform/keycloak/{github,slack}-idp); the directory-sync client
    secret is generated and published to platform/keycloak/directory-sync for the triage agent.
  DESC
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Auth strength — phishing-resistant passkeys (WebAuthn passwordless), no OTP, hardened recovery (#885, §3.1)
# ---------------------------------------------------------------------------

variable "enforce_browser_mfa" {
  description = <<-DESC
    Gates the BINDING of the custom passkey browser flow as the realm's browser flow — the apply-2 flip of the
    two-apply, no-lockout rollout (#885). FALSE (default = apply-1): the flow, the WebAuthn-register-passwordless
    default action, and the realm hardening are all created, but the built-in browser flow stays live so nobody
    is locked out before enrolling a passkey. TRUE (apply-2): bind the new flow — enrolled users log in by
    passkey, new users are force-enrolled. Keycloak is Tier-0, so flip this only AFTER `admin` has enrolled a
    passkey (+ a backup) via the Account Console. `admin-cli` master-realm direct-grant is the break-glass — it's
    independent of any browser flow, so a bad flow never locks out Terraform.
  DESC
  type        = bool
  default     = false
}

variable "session" {
  description = <<-DESC
    Realm session + access-token lifetimes (Go duration strings) — consciously set to limit stolen-token blast
    radius (§3.1 "session lifetime is a tuned dial"). Keep sso_idle_timeout >= the apps' silent-refresh need
    (Backstage relies on Keycloak refresh tokens). The truly role-scoped AWS *console* lifetime (per-permission-
    set session_duration) is owned by the Identity Center generator (#888); these govern the Keycloak/app side.
  DESC
  type = object({
    sso_idle_timeout      = optional(string, "30m")
    sso_max_lifespan      = optional(string, "10h")
    access_token_lifespan = optional(string, "5m")
  })
  default = {}
}

variable "reset_password_allowed" {
  description = "Self-service \"Forgot password\". OFF by default (#885): passkeys are the factor, so recovery is a backup passkey or admin re-provision — a self-service reset would be a phishable backdoor."
  type        = bool
  default     = false
}

variable "password_policy" {
  description = "Keycloak realm password policy string for local (seed/IdP-of-record) accounts. Empty disables it (e.g. when federating, where the upstream owns credentials)."
  type        = string
  default     = "length(14) and notUsername(undefined) and upperCase(1) and lowerCase(1) and digits(1) and specialChars(1) and passwordHistory(3)"
}

variable "brute_force_protection" {
  description = "Realm brute-force detection settings (security_defenses). Enabled by default; tune max_login_failures / lockout behavior here."
  type = object({
    enabled            = optional(bool, true)
    max_login_failures = optional(number, 10)
    permanent_lockout  = optional(bool, false)
  })
  default = {}
}

variable "auth_event_logging" {
  description = "Enable Keycloak login + admin event logging (keycloak_realm_events) — the audit trail for the realm (#885; closes the \"audit-logging off\" gap). Listener defaults to jboss-logging so events land in the pod logs → Loki."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Team taxonomy (the canonical Team registry → Keycloak groups + roles)
# ---------------------------------------------------------------------------

variable "teams" {
  description = <<-DESC
    Canonical Team registry (from infra/live/aws/_teams.hcl, ADR-049/053). Map of team name -> { ssoGroup,
    envelope{allowedEnvironments,...}, and canonical-only fields }. Generates one Keycloak group per team + the
    developer-access roles assigned by envelope. Type `any` to match the crossplane module's `var.teams`. Empty
    = no groups. NOTE: group MEMBERSHIP (which users) is out of scope (SCIM/manual) — claims stay empty until then.
  DESC
  type        = any
  default     = {}
}

variable "platform_groups" {
  description = <<-DESC
    Non-team platform realm groups (e.g. platform-admins, ADR-059), separate from teams: each gets a Keycloak
    group (emitted in the `groups` claim) and — when it carries an `ssoGroup` and the upstream emits groups — an
    advanced-group membership mapper. No tenant envelope/roles (apps match the group name directly). Empty
    ssoGroup leaves membership to a group-emitting upstream / manual assignment (claims stay empty under AWS IdC).
  DESC
  type        = map(object({ ssoGroup = optional(string, "") }))
  default     = { "platform-admins" = {} }
}

variable "tags" {
  description = "Tags applied to the generated Secrets Manager client secrets."
  type        = map(string)
  default     = {}
}
