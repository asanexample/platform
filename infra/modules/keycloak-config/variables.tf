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
# Identity Center SAML broker (federate auth UP to AWS SSO; mirrors the Dex connector)
# ---------------------------------------------------------------------------

variable "saml_idp_alias" {
  description = "Alias of the SAML identity provider (broker). The broker endpoint is <keycloak_url>/realms/<realm>/broker/<alias>/endpoint."
  type        = string
  default     = "aws-sso"
}

variable "saml_sso_url" {
  description = "Identity Center SAML SSO (IdP) URL — the single_sign_on_service_url. From secrets.hcl (keycloak_sso_url)."
  type        = string
}

variable "saml_ca_data" {
  description = "Identity Center IdP signing certificate as the BARE base64 cert body (no PEM -----BEGIN/END----- headers or newlines). See docs/runbooks/keycloak-sso.md. From secrets.hcl (keycloak_sso_ca_data)."
  type        = string
}

variable "saml_entity_id" {
  description = "SP entity id Keycloak presents to Identity Center (the IdC app's SAML audience must match). Empty derives <keycloak_url>/realms/<realm_name>."
  type        = string
  default     = ""
}

variable "saml_email_attribute" {
  description = "Name of the email attribute in the IdC SAML assertion, imported to the Keycloak user's email."
  type        = string
  default     = "email"
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
