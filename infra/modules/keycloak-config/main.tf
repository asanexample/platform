locals {
  create = var.create

  # SP entity id Keycloak presents to Identity Center. The IdC SAML app's audience must equal this.
  sp_entity_id = var.saml_entity_id != "" ? var.saml_entity_id : "${var.keycloak_url}/realms/${var.realm_name}"
}

# ---------------------------------------------------------------------------
# Realm
# ---------------------------------------------------------------------------

resource "keycloak_realm" "this" {
  count = local.create ? 1 : 0

  realm        = var.realm_name
  enabled      = true
  display_name = var.realm_display_name
  # TLS terminates at the Cilium gateway; require HTTPS for external requests only (the in-cluster hop is HTTP).
  ssl_required = "external"
}

# ---------------------------------------------------------------------------
# Identity Center SAML broker — federate authentication up to AWS SSO (ADR-053).
# Mirrors the Dex SAML connector (infra/modules/dex/main.tf): IdC SSO URL + signing cert, email as principal.
# ---------------------------------------------------------------------------

resource "keycloak_saml_identity_provider" "aws_sso" {
  count = local.create ? 1 : 0

  realm        = keycloak_realm.this[0].id
  alias        = var.saml_idp_alias
  display_name = "AWS SSO"
  enabled      = true

  entity_id                  = local.sp_entity_id
  single_sign_on_service_url = var.saml_sso_url
  signing_certificate        = var.saml_ca_data
  validate_signature         = true
  want_assertions_signed     = true

  # Identity Center NameID is the user's email. (Provider uses friendly names, not the URN.)
  name_id_policy_format = "Email"
  principal_type        = "SUBJECT"

  # Brokered users are created/updated on every login; trust the email so they aren't forced to re-verify.
  sync_mode   = "FORCE"
  trust_email = true

  post_binding_response      = true
  post_binding_authn_request = true
}

# Import the SAML email attribute onto the Keycloak user (Dex used emailAttr=email).
resource "keycloak_attribute_importer_identity_provider_mapper" "email" {
  count = local.create ? 1 : 0

  realm                   = keycloak_realm.this[0].id
  name                    = "email"
  identity_provider_alias = keycloak_saml_identity_provider.aws_sso[0].alias
  attribute_name          = var.saml_email_attribute
  user_attribute          = "email"

  extra_config = {
    syncMode = "INHERIT" # inherit the IdP's sync_mode (FORCE)
  }
}
