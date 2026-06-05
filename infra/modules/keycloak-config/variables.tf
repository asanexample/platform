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
