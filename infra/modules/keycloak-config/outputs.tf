output "realm_name" {
  description = "The configured realm name."
  value       = var.realm_name
}

output "realm_id" {
  description = "The realm id (= name)."
  value       = local.create ? keycloak_realm.this[0].id : null
}

output "issuer" {
  description = "OIDC issuer for apps in this realm (<keycloak_url>/realms/<realm>)."
  value       = "${var.keycloak_url}/realms/${var.realm_name}"
}

output "identity_source" {
  description = "Where identity comes from: \"keycloak\" (IdP of record, standalone) or the federated broker protocol (\"saml\" | \"oidc\")."
  value       = local.has_upstream ? local.up.protocol : "keycloak"
}

output "broker_alias" {
  description = "Alias of the upstream identity provider, or null when Keycloak is the IdP of record (no federation)."
  value       = local.has_upstream ? local.up.alias : null
}

output "broker_protocol" {
  description = "Protocol of the upstream broker (saml | oidc), or null when standalone."
  value       = local.has_upstream ? local.up.protocol : null
}

output "broker_endpoint" {
  description = "Broker callback endpoint — the upstream app's ACS (SAML) / redirect URI (OIDC) target. Null when standalone."
  value       = local.has_upstream ? "${var.keycloak_url}/realms/${var.realm_name}/broker/${local.up.alias}/endpoint" : null
}

output "seed_user_secret_names" {
  description = "Secrets Manager names holding each seeded user's temporary password (standalone IdP mode)."
  value       = { for k, v in aws_secretsmanager_secret.user : k => v.name }
}

output "group_membership_mappers" {
  description = "Teams whose upstream group is mapped to a Keycloak group (empty when the upstream emits no groups)."
  value       = keys(local.team_group_bindings)
}

output "client_ids" {
  description = "Registered confidential OIDC client IDs."
  value       = keys(local.clients)
}

output "public_client_ids" {
  description = "Registered public (PKCE, no-secret) OIDC client IDs — e.g. CLI clients."
  value       = keys(local.public_clients)
}

output "client_secret_names" {
  description = "Secrets Manager secret names holding each client's secret (key: client-secret). Each app consumes its secret via an ExternalSecret."
  value       = { for k, v in aws_secretsmanager_secret.client : k => v.name }
}

output "group_names" {
  description = "Keycloak groups created from the Team registry (one per Team)."
  value       = keys(local.teams)
}

output "platform_group_names" {
  description = "Non-team platform groups (e.g. platform-admins)."
  value       = keys(local.platform_groups)
}

output "realm_roles" {
  description = "Developer-access realm roles."
  value       = [for r in keycloak_role.posture : r.name]
}
