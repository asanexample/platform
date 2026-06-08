locals {
  create = var.create

  # Identity source (ADR-059, pluggable seam). DEFAULT: upstream = null -> Keycloak is the IdP of record
  # (standalone; identity lives in this realm via local.users). OPTIONAL federation: set var.upstream to broker
  # auth UP to SAML (e.g. AWS IdC) or OIDC (Okta/Entra/Google) — exactly one IdP is realized; the alias is the
  # stable downstream-facing seam. Every local.up.* read is null-safe so the standalone path needs no upstream.
  up           = var.upstream
  has_upstream = local.create && local.up != null
  is_saml      = local.has_upstream && try(local.up.protocol, "") == "saml"
  is_oidc      = local.has_upstream && try(local.up.protocol, "") == "oidc"
  broker_alias = try(local.up.alias, "")
  group_claim  = try(local.up.group_claim, "")

  # SP entity id Keycloak presents to a SAML upstream. The IdP app's audience must equal this.
  sp_entity_id = try(local.up.saml.entity_id, "") != "" ? local.up.saml.entity_id : "${var.keycloak_url}/realms/${var.realm_name}"

  clients         = local.create ? var.clients : {}
  public_clients  = local.create ? var.public_clients : {}
  oidc_secret_key = "client-secret"

  teams           = local.create ? var.teams : {}
  platform_groups = local.create ? var.platform_groups : {}
  users           = local.create ? var.users : {}

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

  # Per-team upstream-group → Keycloak-group bindings — the membership mechanism for a FEDERATED upstream that
  # emits groups. Empty (mappers inert) when standalone (no upstream) or when the upstream emits no groups
  # (group_claim = "", e.g. AWS IdC). In standalone mode membership comes from local.users instead. Each value is
  # the team's ssoGroup (the match value).
  team_group_bindings = local.group_claim == "" ? {} : {
    for t, cfg in local.teams : t => try(cfg.ssoGroup, "")
    if try(cfg.ssoGroup, "") != ""
  }
  # Same, for non-team platform groups (e.g. platform-admins) that declare an ssoGroup.
  platform_group_bindings = local.group_claim == "" ? {} : {
    for g, cfg in local.platform_groups : g => cfg.ssoGroup
    if try(cfg.ssoGroup, "") != ""
  }
  group_mapper_type = local.is_saml ? "saml-advanced-group-idp-mapper" : "oidc-advanced-group-idp-mapper"

  # Realm group name -> id, across team + platform groups — so seeded users can be placed in groups by name.
  group_id_by_name = merge(
    { for k, g in keycloak_group.team : k => g.id },
    { for k, g in keycloak_group.platform : k => g.id },
  )

  # Default client scopes every client gets. The keycloak_openid_client_default_scopes resource is EXHAUSTIVE,
  # so this lists the Keycloak 26 built-in default client scopes PLUS our `groups` scope.
  default_client_scopes = ["acr", "basic", "email", "profile", "roles", "web-origins", "groups"]
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
  count = local.has_upstream ? 1 : 0

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

# `groups` is a first-class realm CLIENT SCOPE (not a per-client mapper) so any standard OIDC app can request
# `scope=groups` canonically (ArgoCD, Grafana, …) without an `invalid_scope` error. The group-membership mapper
# lives on the scope (bare names, not /path), and the scope is assigned as a DEFAULT scope to every client below,
# so the `groups` claim is in every token AND the scope is requestable.
resource "keycloak_openid_client_scope" "groups" {
  count = local.create ? 1 : 0

  realm_id               = keycloak_realm.this[0].id
  name                   = "groups"
  description            = "Group memberships as a bare-name `groups` claim — the access-model claim apps consume."
  include_in_token_scope = true
}

resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  count = local.create ? 1 : 0

  realm_id        = keycloak_realm.this[0].id
  client_scope_id = keycloak_openid_client_scope.groups[0].id
  name            = "groups"
  claim_name      = "groups"
  full_path       = false
}

# Assign the groups scope to every confidential client. EXHAUSTIVE (the resource manages a client's COMPLETE
# default-scope set), so the Keycloak 26 built-in defaults must be listed too (local.default_client_scopes).
resource "keycloak_openid_client_default_scopes" "confidential" {
  for_each = local.clients

  realm_id       = keycloak_realm.this[0].id
  client_id      = keycloak_openid_client.this[each.key].id
  default_scopes = local.default_client_scopes
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
# Public OIDC clients — for CLIs that can't hold a confidential secret (e.g. the ArgoCD CLI). PKCE S256, NO
# secret, no Secrets Manager entry. Same `groups`/`roles` claim mappers as the confidential clients so CLI
# tokens carry the access-model claims (ADR-059).
# ---------------------------------------------------------------------------

resource "keycloak_openid_client" "public" {
  for_each = local.public_clients

  realm_id                   = keycloak_realm.this[0].id
  client_id                  = each.key
  name                       = each.value.name
  enabled                    = true
  access_type                = "PUBLIC"
  standard_flow_enabled      = true
  valid_redirect_uris        = each.value.redirect_uris
  pkce_code_challenge_method = "S256"
}

# Public clients get the same `groups` scope (default) — so CLI tokens carry the access-model claim.
resource "keycloak_openid_client_default_scopes" "public" {
  for_each = local.public_clients

  realm_id       = keycloak_realm.this[0].id
  client_id      = keycloak_openid_client.public[each.key].id
  default_scopes = local.default_client_scopes
}

resource "keycloak_openid_user_realm_role_protocol_mapper" "public_roles" {
  for_each = local.public_clients

  realm_id    = keycloak_realm.this[0].id
  client_id   = keycloak_openid_client.public[each.key].id
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

# Non-team platform groups (e.g. platform-admins, ADR-059) — emitted in the `groups` claim like team groups, but
# no tenant envelope/roles; apps (ArgoCD/Backstage) match the group name directly (e.g. platform-admins → admin).
resource "keycloak_group" "platform" {
  for_each = local.platform_groups

  realm_id = keycloak_realm.this[0].id
  name     = each.key
}

# ---------------------------------------------------------------------------
# Seeded realm users — the membership source when Keycloak is the IdP of record (ADR-053/059 default, upstream =
# null). Each user is placed directly into its realm groups, so the group→role→claim flow is live without any
# upstream. Passwords are TEMPORARY (must change on first login) and generated into Secrets Manager — never in
# git. When federating instead (var.upstream set), leave var.users empty and let membership flow from the
# upstream group claim. (NOT a substitute for a corporate IdP's lifecycle — seed/admin accounts for non-prod.)
# ---------------------------------------------------------------------------

resource "random_password" "user" {
  for_each = local.users

  length           = 24
  special          = true
  override_special = "-_.!@" # readable + safe to paste; the user rotates it on first login anyway
}

resource "aws_secretsmanager_secret" "user" {
  for_each = local.users

  name                    = "platform/keycloak/seed-user/${each.key}"
  description             = "Temporary (must-change) seed password for Keycloak realm '${var.realm_name}' user '${each.key}'."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "user" {
  for_each = local.users

  secret_id     = aws_secretsmanager_secret.user[each.key].id
  secret_string = jsonencode({ username = each.key, password = random_password.user[each.key].result })
}

resource "keycloak_user" "seed" {
  for_each = local.users

  realm_id       = keycloak_realm.this[0].id
  username       = each.key
  email          = each.value.email
  email_verified = true
  enabled        = true
  first_name     = each.value.first_name
  last_name      = each.value.last_name

  initial_password {
    value     = random_password.user[each.key].result
    temporary = true # forces a password change on first login
  }

  lifecycle {
    # temporary=true makes Keycloak set an UPDATE_PASSWORD required action, which it then CLEARS once the user
    # changes their password at first login. We don't manage required_actions, so terraform would otherwise keep
    # trying to reset them on every apply — stripping the forced-change before a user logs in, or re-adding it
    # after they've changed their password. Let Keycloak/the user own it. (initial_password is write-only —
    # ignored so a password the user has since rotated isn't reset back to the generated seed value.)
    ignore_changes = [required_actions, initial_password]
  }
}

# Exhaustive group membership for each seeded user — by group name (team or platform group).
resource "keycloak_user_groups" "seed" {
  for_each = { for u, cfg in local.users : u => cfg if length(cfg.groups) > 0 }

  realm_id   = keycloak_realm.this[0].id
  user_id    = keycloak_user.seed[each.key].id
  exhaustive = true
  group_ids  = [for g in each.value.groups : local.group_id_by_name[g]]
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

# Same membership mechanism for the non-team platform groups (e.g. platform-admins). Inert under AWS IdC.
resource "keycloak_custom_identity_provider_mapper" "platform_group" {
  for_each = local.platform_group_bindings

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
    keycloak_group.platform,
    keycloak_saml_identity_provider.upstream,
    keycloak_oidc_identity_provider.upstream,
  ]
}
