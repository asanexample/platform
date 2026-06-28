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

  # Auth strength (#885, identity strategy §3.1). Phishing-resistant passkeys (WebAuthn passwordless), NO OTP —
  # the factor lives HERE because Keycloak is the IdP of record. Built only for the standalone realm: when
  # federating, the upstream owns the factor and assurance is honored across the seam (ADR-059), so the local
  # passkey flow is inert.
  manage_mfa = local.create && !local.has_upstream

  # Master-realm admin-plane hardening (#899, ADR-087). Opt-in passkey on the master *browser* (human console)
  # flow — closes the master-console MFA bypass. Does NOT touch admin-cli's direct-grant (the bootstrap +
  # break-glass path, which MUST survive). The master realm's keycloak_realm object is deliberately NOT managed
  # here, so master resources target realm_id = "master" directly and rely on master's default WebAuthn policy.
  manage_master = local.create && var.manage_master_admin

  # The WebAuthn Relying Party id MUST be the registrable domain Keycloak is served from (bare host, no scheme
  # or path) or browsers reject the credential. Derived from keycloak_url (e.g. https://keycloak.aws.refplat.org).
  # NOTE: changing this host invalidates every enrolled passkey — settle the hostname before rollout.
  kc_host = split("/", replace(replace(var.keycloak_url, "https://", ""), "http://", ""))[0]

  # acr ↔ Level-of-Authentication map (the assurance seam, §3.1). Defines the assurance vocabulary apps can read
  # off the `acr` claim and that step-up at elevation (P3 / #361's temporary-power checkout) requests via
  # acr_values; the passkey flow below is the standing factor, step-up conditions are layered by P3.
  acr_loa_map = { gold = 2, silver = 1 }
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

  # Short, consciously-set session + token lifetimes (§3.1 "session lifetime is a tuned dial") — limit the blast
  # radius of a stolen token. The role-scoped AWS *console* lifetime is owned by the IdC generator (#888).
  sso_session_idle_timeout = var.session.sso_idle_timeout
  sso_session_max_lifespan = var.session.sso_max_lifespan
  access_token_lifespan    = var.session.access_token_lifespan

  # Recovery hardening (#885): self-service "Forgot password" OFF — passkeys are the factor, so recovery is a
  # backup passkey or admin re-provision; a self-service reset would be a phishable backdoor. The password policy
  # still governs the seed accounts' first factor.
  reset_password_allowed = var.reset_password_allowed
  password_policy        = var.password_policy

  # Phishing-resistant passkeys (WebAuthn PASSWORDLESS) are the realm's MFA factor — no OTP anywhere (OTP is
  # phishable: an attacker-in-the-middle relays it). The Relying Party id is the host Keycloak is served from;
  # user verification + a resident (discoverable) key are REQUIRED. Signature algs cover platform (ES256) +
  # cross-platform (RS256) authenticators. The passwordless authenticator in the browser flow uses this policy.
  web_authn_passwordless_policy {
    relying_party_entity_name     = var.realm_display_name
    relying_party_id              = local.kc_host
    signature_algorithms          = ["ES256", "RS256"]
    user_verification_requirement = "required"
    require_resident_key          = "Yes"
  }

  # Brute-force detection — slow down credential stuffing against local accounts.
  dynamic "security_defenses" {
    for_each = var.brute_force_protection.enabled ? [1] : []
    content {
      brute_force_detection {
        max_login_failures = var.brute_force_protection.max_login_failures
        permanent_lockout  = var.brute_force_protection.permanent_lockout
      }
    }
  }

  # acr ↔ LoA assurance map — the vocabulary apps read off the `acr` claim and that step-up requests (P3, §3.1).
  # Set unconditionally (not gated on enforce_strong_auth): assurance is invariant across the IdP seam, and gating
  # it would churn a realm-attribute write on every federation flip (racing the flow-binding revert).
  attributes = local.create ? { "acr.loa.map" = jsonencode(local.acr_loa_map) } : {}
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
# Per-app OIDC clients — each app's registration in the realm (ADR-053/059).
# Confidential clients with a generated secret (stored in Secrets Manager at platform/keycloak/<id>-oidc) +
# a `groups` claim mapper. Each app (ArgoCD, Backstage, Grafana) consumes its secret via an ExternalSecret.
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

# Preprod-account replica of selected client secrets (var.replicate_client_secrets_to_preprod) — same name + JSON
# shape, written via the aws.preprod provider, so the spoke cluster's ESO reads the shared secret locally (the
# Keycloak client is shared; only its secret is copied). Avoids cross-account KMS on the platform secret.
resource "aws_secretsmanager_secret" "client_preprod" {
  for_each = local.create ? toset([for c in var.replicate_client_secrets_to_preprod : c if contains(keys(local.clients), c)]) : toset([])
  provider = aws.preprod

  # `preprod/` prefix so the preprod ESO role (scoped to `secret:preprod/*`) can read it — NOT `platform/`.
  name                    = "preprod/keycloak/${each.key}-oidc"
  description             = "Keycloak OIDC client secret for ${local.clients[each.key].name} (realm ${var.realm_name}) — preprod replica of the platform secret."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "client_preprod" {
  for_each = aws_secretsmanager_secret.client_preprod
  provider = aws.preprod

  secret_id     = each.value.id
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

  # RP-initiated logout: allow these post-logout redirect targets (Keycloak validates the
  # post_logout_redirect_uri the app sends to the end-session endpoint). "+" = inherit valid_redirect_uris.
  valid_post_logout_redirect_uris = length(each.value.post_logout_redirect_uris) > 0 ? each.value.post_logout_redirect_uris : ["+"]
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
    #
    # federated_identity: a seed user can broker-link their GitHub/Slack accounts via the Keycloak Account Console
    # (ADR-084 owner-routing — the triage agent's directory-sync reads these federated identities as the
    # AUTHORITATIVE source for the @mention handle map). We declare NONE here (they're runtime, OAuth-discovered, and
    # MUST NOT live in git), so without this ignore an apply reconciles the user to federatedIdentities:[] and SILENTLY
    # deletes every console-linked account — which is exactly what wiped josh's github/slack links and dropped
    # owner-routing to channel-level (a stray keycloak-config apply, not a park, was the trigger). IaC owns the user;
    # the runtime owns the brokered links.
    ignore_changes = [required_actions, initial_password, federated_identity]
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

# ---------------------------------------------------------------------------
# Account linking — broker GitHub + Slack as LINKABLE identity providers (ADR-084 Phase 1). A person links
# their accounts once via the Account Console; the directory-sync service account then reads the resulting
# federated identities so the triage agent can resolve a culprit commit's author → their Slack @mention.
# Off by default (var.enable_account_linking); the two IdP app secrets are read from Secrets Manager. The IdPs
# are hidden from the login page — this is for LINKING (an authenticated user), not a login option.
# ---------------------------------------------------------------------------

locals {
  enable_linking = local.create && var.enable_account_linking
  gh             = local.enable_linking ? jsondecode(data.aws_secretsmanager_secret_version.github_idp[0].secret_string) : {}
  sl             = local.enable_linking ? jsondecode(data.aws_secretsmanager_secret_version.slack_idp[0].secret_string) : {}
}

data "aws_secretsmanager_secret_version" "github_idp" {
  count     = local.enable_linking ? 1 : 0
  secret_id = "platform/keycloak/github-idp"
}

data "aws_secretsmanager_secret_version" "slack_idp" {
  count     = local.enable_linking ? 1 : 0
  secret_id = "platform/keycloak/slack-idp"
}

# GitHub — Keycloak's built-in `github` social provider (OAuth2 + api.github.com/user; GitHub is NOT OIDC, so
# provider_id selects the github implementation). No id_token → no signature validation.
resource "keycloak_oidc_identity_provider" "github" {
  count = local.enable_linking ? 1 : 0

  realm              = keycloak_realm.this[0].id
  alias              = "github"
  provider_id        = "github"
  display_name       = "GitHub"
  enabled            = true
  hide_on_login_page = true

  authorization_url = "https://github.com/login/oauth/authorize"
  token_url         = "https://github.com/login/oauth/access_token"
  user_info_url     = "https://api.github.com/user"
  client_id         = local.gh["client-id"]
  client_secret     = local.gh["client-secret"]
  default_scopes    = "read:user user:email"

  sync_mode   = "FORCE"
  trust_email = true
  store_token = false
}

# Slack — "Sign in with Slack" (OpenID Connect). The Slack user id is the standard `sub` claim ("U…").
resource "keycloak_oidc_identity_provider" "slack" {
  count = local.enable_linking ? 1 : 0

  realm              = keycloak_realm.this[0].id
  alias              = "slack"
  display_name       = "Slack"
  enabled            = true
  hide_on_login_page = true

  authorization_url = "https://slack.com/openid/connect/authorize"
  token_url         = "https://slack.com/api/openid.connect.token"
  user_info_url     = "https://slack.com/api/openid.connect.userInfo"
  jwks_url          = "https://slack.com/openid/connect/keys"
  client_id         = local.sl["client-id"]
  client_secret     = local.sl["client-secret"]
  default_scopes    = "openid profile email"

  validate_signature = true
  sync_mode          = "FORCE"
  trust_email        = true
  store_token        = false
}

# Project each provider's native id onto a Keycloak user attribute — the directory-sync reads these. GitHub's
# profile `login` matches a commit author.login; Slack's `sub` is the U… id the agent renders as <@U…>.
resource "keycloak_attribute_importer_identity_provider_mapper" "github_login" {
  count = local.enable_linking ? 1 : 0

  realm                   = keycloak_realm.this[0].id
  name                    = "github-login"
  identity_provider_alias = "github"
  claim_name              = "login"
  user_attribute          = "githubLogin"
  extra_config            = { syncMode = "INHERIT" }

  depends_on = [keycloak_oidc_identity_provider.github]
}

resource "keycloak_attribute_importer_identity_provider_mapper" "slack_userid" {
  count = local.enable_linking ? 1 : 0

  realm                   = keycloak_realm.this[0].id
  name                    = "slack-userid"
  identity_provider_alias = "slack"
  claim_name              = "sub"
  user_attribute          = "slackUserId"
  extra_config            = { syncMode = "INHERIT" }

  depends_on = [keycloak_oidc_identity_provider.slack]
}

# directory-sync service account — the triage agent's directory reads users + their federated identities as this
# client (client-credentials), granted realm-management `view-users` (read-only). Its secret is published to SM
# for the agent's ExternalSecret (platform/keycloak/directory-sync).
resource "random_password" "directory_sync" {
  count   = local.enable_linking ? 1 : 0
  length  = 40
  special = false
}

resource "keycloak_openid_client" "directory_sync" {
  count = local.enable_linking ? 1 : 0

  realm_id                     = keycloak_realm.this[0].id
  client_id                    = "directory-sync"
  name                         = "Directory Sync (ADR-084)"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = true
  client_secret                = random_password.directory_sync[0].result
}

data "keycloak_openid_client" "realm_management" {
  count     = local.enable_linking ? 1 : 0
  realm_id  = keycloak_realm.this[0].id
  client_id = "realm-management"
}

resource "keycloak_openid_client_service_account_role" "directory_sync_view_users" {
  count = local.enable_linking ? 1 : 0

  realm_id                = keycloak_realm.this[0].id
  service_account_user_id = keycloak_openid_client.directory_sync[0].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management[0].id
  role                    = "view-users"
}

resource "aws_secretsmanager_secret" "directory_sync" {
  count = local.enable_linking ? 1 : 0

  name                    = "platform/keycloak/directory-sync"
  description             = "Keycloak directory-sync service-account client secret (ADR-084 Phase 1)."
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "directory_sync" {
  count = local.enable_linking ? 1 : 0

  secret_id     = aws_secretsmanager_secret.directory_sync[0].id
  secret_string = jsonencode({ "client-secret" = random_password.directory_sync[0].result })
}


# ---------------------------------------------------------------------------
# Auth strength — phishing-resistant passkeys + hardened recovery (#885, identity strategy §3.1)
#
# A custom BROWSER flow requires a phishing-resistant passkey (WebAuthn PASSWORDLESS) for ALL workforce — no OTP
# anywhere (OTP is phishable via an attacker-in-the-middle relay). Recovery is a backup passkey or admin
# re-provision, not a self-service password reset (that would be the backdoor). New users are force-enrolled by
# a default required action. Auth events are logged for the audit trail.
#
# Tier-0 no-lockout discipline: the flow + required action + realm hardening are created on apply-1, but the
# BINDING (making it the realm's browser flow) is gated behind var.enforce_browser_mfa — flip it true on apply-2
# only AFTER `admin` has enrolled a passkey. `admin-cli`'s master-realm direct-grant is the break-glass, so a bad
# flow never locks out Terraform. Built only for the STANDALONE realm (local.manage_mfa) — when federating, the
# upstream owns the factor and assurance is honored across the seam (ADR-059).
#
# Ordering: the Keycloak API orders sibling executions by `priority`; we also chain depends_on between siblings
# so terraform CREATES them in that order (the provider appends to the flow, so creation order must match).
# ---------------------------------------------------------------------------

# Login + admin event logging — the realm's audit trail (closes the "audit-logging off" gap). jboss-logging
# lands events in the Keycloak pod logs → Loki. Applies regardless of the MFA flow (realm-level posture).
resource "keycloak_realm_events" "this" {
  count = local.create && var.auth_event_logging ? 1 : 0

  realm_id = keycloak_realm.this[0].id

  events_enabled    = true
  events_expiration = 604800 # 7 days of login events retained in Keycloak's store

  admin_events_enabled         = true
  admin_events_details_enabled = true

  events_listeners = ["jboss-logging"]
}

# Force every new user to enroll a passkey (the realm's only factor). default_action stamps NEW users at first
# login; it does not retroactively prompt existing users — those are force-enrolled in-flow by the REQUIRED
# passwordless execution below. Uses the PASSWORDLESS register action (not the 2FA webauthn-register).
resource "keycloak_required_action" "webauthn_register_passwordless" {
  count = local.manage_mfa ? 1 : 0

  realm_id       = keycloak_realm.this[0].id
  alias          = "webauthn-register-passwordless"
  enabled        = true
  default_action = true
}

# --- Browser flow — password + a required passkey, no OTP --------------------

resource "keycloak_authentication_flow" "browser" {
  count = local.manage_mfa ? 1 : 0

  realm_id    = keycloak_realm.this[0].id
  alias       = "platform-browser"
  provider_id = "basic-flow"
  description = "Browser login requiring a phishing-resistant passkey for all workforce (#885)."
}

# Cookie + IdP redirector at the top (ALTERNATIVE) so an existing SSO cookie or a brokered/social login still
# short-circuits the username/password + passkey path.
resource "keycloak_authentication_execution" "browser_cookie" {
  count = local.manage_mfa ? 1 : 0

  realm_id          = keycloak_realm.this[0].id
  parent_flow_alias = keycloak_authentication_flow.browser[0].alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_execution" "browser_idp" {
  count = local.manage_mfa ? 1 : 0

  realm_id          = keycloak_realm.this[0].id
  parent_flow_alias = keycloak_authentication_flow.browser[0].alias
  authenticator     = "identity-provider-redirector"
  requirement       = "ALTERNATIVE"
  priority          = 20
  depends_on        = [keycloak_authentication_execution.browser_cookie]
}

# The forms subflow MUST be ALTERNATIVE (not REQUIRED) — a REQUIRED sibling would defeat the cookie/IdP
# short-circuit above and force the password form even on an existing SSO session.
resource "keycloak_authentication_subflow" "browser_forms" {
  count = local.manage_mfa ? 1 : 0

  realm_id          = keycloak_realm.this[0].id
  parent_flow_alias = keycloak_authentication_flow.browser[0].alias
  alias             = "platform-browser-forms"
  requirement       = "ALTERNATIVE"
  priority          = 30
  depends_on        = [keycloak_authentication_execution.browser_idp]
}

resource "keycloak_authentication_execution" "forms_userpass" {
  count = local.manage_mfa ? 1 : 0

  realm_id          = keycloak_realm.this[0].id
  parent_flow_alias = keycloak_authentication_subflow.browser_forms[0].alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

# REQUIRED passkey for everyone — a REQUIRED passwordless execution with no credential triggers passkey
# registration in-flow, so even a user the default action missed is force-enrolled before they can finish login.
resource "keycloak_authentication_subflow" "browser_mfa" {
  count = local.manage_mfa ? 1 : 0

  realm_id          = keycloak_realm.this[0].id
  parent_flow_alias = keycloak_authentication_subflow.browser_forms[0].alias
  alias             = "platform-browser-mfa"
  requirement       = "REQUIRED"
  priority          = 20
  depends_on        = [keycloak_authentication_execution.forms_userpass]
}

resource "keycloak_authentication_execution" "mfa_webauthn" {
  count = local.manage_mfa ? 1 : 0

  realm_id          = keycloak_realm.this[0].id
  parent_flow_alias = keycloak_authentication_subflow.browser_mfa[0].alias
  authenticator     = "webauthn-authenticator-passwordless"
  requirement       = "REQUIRED"
  priority          = 10
}

# --- Gated binding — the apply-2 flip ---------------------------------------

# Bind the passkey flow as the realm's browser flow ONLY when enforce_browser_mfa is true (apply-2). On apply-1
# this resource is absent, so the built-in browser flow stays live and nobody is locked out before enrolling.
# Separate resource (not the realm's browser_flow attribute) to avoid a realm <-> flow dependency cycle.
resource "keycloak_authentication_bindings" "this" {
  count = local.manage_mfa && var.enforce_browser_mfa ? 1 : 0

  realm_id     = keycloak_realm.this[0].id
  browser_flow = keycloak_authentication_flow.browser[0].alias
}

# ---------------------------------------------------------------------------
# Master-realm admin-plane hardening (#899, ADR-087) — a passkey on the MASTER browser flow
#
# Terraform authenticates as the master-realm `admin` user (admin-cli), a near-superuser that bypasses the
# platform-realm MFA above. MFA on the master *browser* flow closes the HUMAN-CONSOLE bypass (a person logging
# into the master realm UI), mirroring the #885 platform flow with realm_id = "master". It does NOT — and must
# not — touch admin-cli's DIRECT-GRANT flow: that is the greenfield bootstrap + the break-glass, and disabling it
# bricks every rebuild (INVARIANT, ADR-087). The master realm's keycloak_realm object is deliberately NOT brought
# under management, so these target realm_id = "master" and use master's DEFAULT WebAuthn passwordless policy
# (RP id defaults to the request host, the same keycloak host). Same two-apply, no-lockout rollout as #885: built
# when manage_master_admin, BOUND only when enforce_master_browser_mfa — enroll a passkey on the master `admin`
# first. Opt-in (default off). state_purge drops keycloak_* on teardown, so these purge with the rest.
# ---------------------------------------------------------------------------

resource "keycloak_required_action" "master_webauthn_register_passwordless" {
  count = local.manage_master ? 1 : 0

  realm_id       = "master"
  alias          = "webauthn-register-passwordless"
  enabled        = true
  default_action = true
}

resource "keycloak_authentication_flow" "master_browser" {
  count = local.manage_master ? 1 : 0

  realm_id    = "master"
  alias       = "master-passkey-browser"
  provider_id = "basic-flow"
  description = "Master-realm console login requiring a phishing-resistant passkey (#899). admin-cli direct-grant is unaffected."
}

resource "keycloak_authentication_execution" "master_cookie" {
  count = local.manage_master ? 1 : 0

  realm_id          = "master"
  parent_flow_alias = keycloak_authentication_flow.master_browser[0].alias
  authenticator     = "auth-cookie"
  requirement       = "ALTERNATIVE"
  priority          = 10
}

resource "keycloak_authentication_execution" "master_idp" {
  count = local.manage_master ? 1 : 0

  realm_id          = "master"
  parent_flow_alias = keycloak_authentication_flow.master_browser[0].alias
  authenticator     = "identity-provider-redirector"
  requirement       = "ALTERNATIVE"
  priority          = 20
  depends_on        = [keycloak_authentication_execution.master_cookie]
}

resource "keycloak_authentication_subflow" "master_forms" {
  count = local.manage_master ? 1 : 0

  realm_id          = "master"
  parent_flow_alias = keycloak_authentication_flow.master_browser[0].alias
  alias             = "master-passkey-forms"
  requirement       = "ALTERNATIVE"
  priority          = 30
  depends_on        = [keycloak_authentication_execution.master_idp]
}

resource "keycloak_authentication_execution" "master_userpass" {
  count = local.manage_master ? 1 : 0

  realm_id          = "master"
  parent_flow_alias = keycloak_authentication_subflow.master_forms[0].alias
  authenticator     = "auth-username-password-form"
  requirement       = "REQUIRED"
  priority          = 10
}

resource "keycloak_authentication_subflow" "master_mfa" {
  count = local.manage_master ? 1 : 0

  realm_id          = "master"
  parent_flow_alias = keycloak_authentication_subflow.master_forms[0].alias
  alias             = "master-passkey-mfa"
  requirement       = "REQUIRED"
  priority          = 20
  depends_on        = [keycloak_authentication_execution.master_userpass]
}

resource "keycloak_authentication_execution" "master_mfa_webauthn" {
  count = local.manage_master ? 1 : 0

  realm_id          = "master"
  parent_flow_alias = keycloak_authentication_subflow.master_mfa[0].alias
  authenticator     = "webauthn-authenticator-passwordless"
  requirement       = "REQUIRED"
  priority          = 10
}

# Gated binding (apply-2). Bind master's browser flow ONLY when enforce_master_browser_mfa — until then the
# built-in master browser flow stays live so the admin console isn't locked out before enrolling a passkey.
resource "keycloak_authentication_bindings" "master" {
  count = local.manage_master && var.enforce_master_browser_mfa ? 1 : 0

  realm_id     = "master"
  browser_flow = keycloak_authentication_flow.master_browser[0].alias
}
