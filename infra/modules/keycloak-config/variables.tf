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
    The upstream IdP Keycloak brokers authentication to (ADR-059). `protocol` selects SAML (e.g. AWS Identity
    Center) or OIDC (Okta / Entra / Google); fill the matching sub-object. `group_claim` is the name of the group
    claim/attribute the upstream emits — set it (e.g. "groups") to drive the per-team membership mappers; ""
    (the default, and AWS IdC's reality) leaves them inert. The broker endpoint is
    <keycloak_url>/realms/<realm>/broker/<alias>/endpoint.
  DESC
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

  validation {
    condition     = contains(["saml", "oidc"], var.upstream.protocol)
    error_message = "upstream.protocol must be \"saml\" or \"oidc\"."
  }
  validation {
    condition     = var.upstream.protocol != "saml" || var.upstream.saml != null
    error_message = "upstream.saml must be set when protocol = \"saml\"."
  }
  validation {
    condition     = var.upstream.protocol != "oidc" || var.upstream.oidc != null
    error_message = "upstream.oidc must be set when protocol = \"oidc\"."
  }
  validation {
    condition     = var.upstream.protocol != "oidc" || var.upstream_oidc_client_secret != ""
    error_message = "upstream_oidc_client_secret must be set when protocol = \"oidc\"."
  }
}

variable "upstream_oidc_client_secret" {
  description = "OIDC client secret for the upstream broker app (required when upstream.protocol = \"oidc\"; from secrets.hcl). Unused for SAML."
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Per-app OIDC clients
# ---------------------------------------------------------------------------

variable "clients" {
  description = <<-DESC
    OIDC clients to register in the realm. Each gets a confidential client + a `groups` claim mapper + a
    generated secret stored in Secrets Manager at platform/keycloak/<id>-oidc (a Keycloak-specific path, so it
    does NOT collide with Dex's platform/<id>/oidc during coexistence). Apps repoint to these at the B3/B4
    cutover. Add a client here to onboard another app.
  DESC
  type = map(object({
    name          = string
    redirect_uris = list(string)
  }))
  default = {
    argocd = {
      name          = "ArgoCD"
      redirect_uris = ["https://argocd.aws.refplat.org/auth/callback", "http://localhost:8085/auth/callback"]
    }
    backstage = {
      name          = "Backstage"
      redirect_uris = ["https://backstage.aws.refplat.org/api/auth/oidc/handler/frame"]
    }
    "oauth2-proxy" = {
      name          = "OAuth2 Proxy (Backstage)"
      redirect_uris = ["https://backstage.aws.refplat.org/oauth2/callback"]
    }
  }
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for generated client secrets. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
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

variable "tags" {
  description = "Tags applied to the generated Secrets Manager client secrets."
  type        = map(string)
  default     = {}
}
