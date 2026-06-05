locals {
  create = var.create

  # Upstream broker (ADR-059): one of SAML | OIDC is realized; the alias is the stable downstream-facing seam.
  up           = var.upstream
  is_saml      = local.create && local.up.protocol == "saml"
  is_oidc      = local.create && local.up.protocol == "oidc"
  broker_alias = local.up.alias

  # SP entity id Keycloak presents to a SAML upstream. The IdP app's audience must equal this.
  sp_entity_id = try(local.up.saml.entity_id, "") != "" ? local.up.saml.entity_id : "${var.keycloak_url}/realms/${var.realm_name}"

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

  # Per-team upstream-group → Keycloak-group bindings. Empty (mappers inert) when the upstream emits no groups
  # (group_claim = "", e.g. AWS IdC — ADR-059 scenario C). each value is the team's ssoGroup (the match value).
  team_group_bindings = local.up.group_claim == "" ? {} : {
    for t, cfg in local.teams : t => try(cfg.ssoGroup, "")
    if try(cfg.ssoGroup, "") != ""
  }
  group_mapper_type = local.is_saml ? "saml-advanced-group-idp-mapper" : "oidc-advanced-group-idp-mapper"
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
# Upstream broker — federate authentication UP to the configured IdP (ADR-053/059). Pluggable: exactly one of
# the SAML / OIDC providers below is realized by var.upstream.protocol. The alias is the stable downstream seam.
# ---------------------------------------------------------------------------

# SAML upstream (e.g. AWS Identity Center; mirrors the Dex connector — IdP SSO URL + signing cert, email principal).
resource "keycloak_saml_identity_provider" "upstream" {
  count = local.is_saml ? 1 : 0

  realm        = keycloak_realm.this[0].id
  alias        = local.up.alias
  display_name = local.up.display_name
  enabled      = true

  entity_id                  = local.sp_entity_id
  single_sign_on_service_url = local.up.saml.sso_url
  signing_certificate        = local.up.saml.ca_data
  validate_signature         = true
  want_assertions_signed     = local.up.saml.want_assertions_signed

  # IdP NameID is the user's email. (Provider uses friendly names, not the URN.)
  name_id_policy_format = local.up.saml.name_id_format
  principal_type        = local.up.saml.principal_type

  # Brokered users are created/updated on every login; trust the email so they aren't forced to re-verify.
  sync_mode   = "FORCE"
  trust_email = true

  post_binding_response      = true
  post_binding_authn_request = true
}

# OIDC upstream (e.g. Okta / Entra / Google). Endpoints + confidential client come from var.upstream.oidc + the
# separate sensitive client-secret var. Signature validation is enabled only when a JWKS URL is provided.
resource "keycloak_oidc_identity_provider" "upstream" {
  count = local.is_oidc ? 1 : 0

  realm        = keycloak_realm.this[0].id
  alias        = local.up.alias
  display_name = local.up.display_name
  enabled      = true

  authorization_url = local.up.oidc.authorization_url
  token_url         = local.up.oidc.token_url
  user_info_url     = local.up.oidc.user_info_url
  jwks_url          = local.up.oidc.jwks_url
  client_id         = local.up.oidc.client_id
  client_secret     = var.upstream_oidc_client_secret
  default_scopes    = local.up.oidc.default_scopes

  validate_signature = local.up.oidc.jwks_url != ""

  sync_mode   = "FORCE"
  trust_email = true
  store_token = false
}

# Import the upstream email onto the Keycloak user. SAML uses attribute_name; OIDC uses claim_name — the unused
# one stays null. identity_provider_alias is the (string) broker alias, so depends_on pins the IdP ordering.
resource "keycloak_attribute_importer_identity_provider_mapper" "email" {
  count = local.create ? 1 : 0

  realm                   = keycloak_realm.this[0].id
  name                    = "email"
  identity_provider_alias = local.broker_alias
  attribute_name          = local.is_saml ? local.up.email_attribute : null
  claim_name              = local.is_oidc ? local.up.email_attribute : null
  user_attribute          = "email"

  extra_config = {
    syncMode = "INHERIT" # inherit the IdP's sync_mode (FORCE)
  }

  depends_on = [
    keycloak_saml_identity_provider.upstream,
    keycloak_oidc_identity_provider.upstream,
  ]
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
# each group by its envelope. Membership (which users join each group) is driven by the upstream group mappers
# below — inert until a group-emitting upstream is wired (ADR-059).
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

# ---------------------------------------------------------------------------
# Upstream group → Keycloak group membership (ADR-059, the membership mechanism). One advanced-group IdP mapper
# per Team: when the brokered login's group claim/attribute (var.upstream.group_claim) carries the team's
# ssoGroup value, the user JOINS the Keycloak group `/<team>` and so inherits its roles — populating both the
# `groups` and `roles` claims (vs a pass-through, which would bypass the #230 group→role taxonomy). FORCE sync
# re-evaluates each login (add + remove). Empty (inert) when the upstream emits no groups — e.g. AWS IdC.
# ---------------------------------------------------------------------------

resource "keycloak_custom_identity_provider_mapper" "team_group" {
  for_each = local.team_group_bindings

  realm                    = keycloak_realm.this[0].id
  name                     = "group-${each.key}"
  identity_provider_alias  = local.broker_alias
  identity_provider_mapper = local.group_mapper_type

  extra_config = merge(
    {
      syncMode                 = "INHERIT"
      group                    = "/${each.key}"
      "are.claim.values.regex" = "false"
    },
    local.is_saml
    ? { attributes = jsonencode([{ key = local.up.group_claim, value = each.value }]) }
    : { claims = jsonencode([{ key = local.up.group_claim, value = each.value }]) }
  )

  depends_on = [
    keycloak_group.team,
    keycloak_saml_identity_provider.upstream,
    keycloak_oidc_identity_provider.upstream,
  ]
}
