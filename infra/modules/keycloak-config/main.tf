locals {
  create = var.create

  # SP entity id Keycloak presents to Identity Center. The IdC SAML app's audience must equal this.
  sp_entity_id = var.saml_entity_id != "" ? var.saml_entity_id : "${var.keycloak_url}/realms/${var.realm_name}"

  clients         = local.create ? var.clients : {}
  oidc_secret_key = "client-secret"

  teams = local.create ? var.teams : {}

  # ADR-049 standing developer-access posture by environment (elevation is break-glass, not a standing role).
  role_for_env = {
    preprod = "tenant-operate"
    prod    = "tenant-view"
  }
  posture_roles = ["tenant-operate", "tenant-view"]

  # Roles each team's group gets, derived from its envelope.allowedEnvironments.
  team_role_names = {
    for t, cfg in local.teams : t => distinct(compact([
      for env in try(cfg.envelope.allowedEnvironments, []) : lookup(local.role_for_env, env, "")
    ]))
  }
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

# ---------------------------------------------------------------------------
# Per-app OIDC clients — each app's registration in the realm (ADR-053).
# Confidential clients with a generated secret (stored in Secrets Manager, Keycloak-specific path so it does
# NOT collide with Dex's platform/<id>/oidc during coexistence) + a `groups` claim mapper. Apps repoint to
# these at the B3/B4 cutover; nothing consumes them yet.
# ---------------------------------------------------------------------------

resource "random_password" "client" {
  for_each = local.clients

  length  = 40
  special = false # alphanumeric — safe across the SM->ESO->app path
}

resource "aws_secretsmanager_secret" "client" {
  for_each = local.clients

  name                    = "platform/keycloak/${each.key}-oidc"
  description             = "Keycloak OIDC client secret for ${each.value.name} (realm ${var.realm_name})."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "client" {
  for_each = local.clients

  secret_id     = aws_secretsmanager_secret.client[each.key].id
  secret_string = jsonencode({ (local.oidc_secret_key) = random_password.client[each.key].result })
}

resource "keycloak_openid_client" "this" {
  for_each = local.clients

  realm_id              = keycloak_realm.this[0].id
  client_id             = each.key
  name                  = each.value.name
  enabled               = true
  access_type           = "CONFIDENTIAL"
  standard_flow_enabled = true
  valid_redirect_uris   = each.value.redirect_uris
  client_secret         = random_password.client[each.key].result
}

# Emit the user's group memberships as a `groups` claim (bare names, not /path) — the access-model claim apps
# consume. Inert until the Team→group taxonomy slice populates groups.
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  for_each = local.clients

  realm_id   = keycloak_realm.this[0].id
  client_id  = keycloak_openid_client.this[each.key].id
  name       = "groups"
  claim_name = "groups"
  full_path  = false
}

# Emit the user's realm roles as a `roles` claim per client (alongside `groups`). NOTE: this emits ALL realm
# roles incl. Keycloak defaults (offline_access, default-roles-platform, …); apps filter to the tenant-* roles.
resource "keycloak_openid_user_realm_role_protocol_mapper" "roles" {
  for_each = local.clients

  realm_id    = keycloak_realm.this[0].id
  client_id   = keycloak_openid_client.this[each.key].id
  name        = "roles"
  claim_name  = "roles"
  multivalued = true
}

# ---------------------------------------------------------------------------
# Team taxonomy — Keycloak groups + developer-access roles, generated from the canonical registry (ADR-053).
# One group per Team (the named `groups` claim apps consume); realm roles for the ADR-049 posture, assigned to
# each group by its envelope. Group MEMBERSHIP (which users) is out of scope (SCIM/manual) — claims stay empty
# until membership lands, which the B3/B4 app cutovers depend on.
# ---------------------------------------------------------------------------

resource "keycloak_group" "team" {
  for_each = local.teams

  realm_id = keycloak_realm.this[0].id
  name     = each.key
}

resource "keycloak_role" "posture" {
  for_each = local.create ? toset(local.posture_roles) : toset([])

  realm_id = keycloak_realm.this[0].id
  name     = each.value
  description = (each.value == "tenant-operate"
    ? "Standing developer access in preprod — operate (ADR-049/040; elevation via break-glass)."
  : "Standing developer access in prod — view (operate via break-glass; ADR-049/040).")
}

resource "keycloak_group_roles" "team" {
  for_each = local.teams

  realm_id   = keycloak_realm.this[0].id
  group_id   = keycloak_group.team[each.key].id
  exhaustive = true
  role_ids   = [for r in local.team_role_names[each.key] : keycloak_role.posture[r].id]
}
