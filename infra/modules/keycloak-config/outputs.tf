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

output "broker_alias" {
  description = "Alias of the Identity Center SAML broker."
  value       = var.saml_idp_alias
}

output "broker_endpoint" {
  description = "SAML broker ACS endpoint (the IdC app's ACS/audience target)."
  value       = "${var.keycloak_url}/realms/${var.realm_name}/broker/${var.saml_idp_alias}/endpoint"
}

output "client_ids" {
  description = "Registered OIDC client IDs."
  value       = keys(local.clients)
}

output "client_secret_names" {
  description = "Secrets Manager secret names holding each client's secret (key: client-secret). Apps consume these at the B3/B4 cutover."
  value       = { for k, v in aws_secretsmanager_secret.client : k => v.name }
}

output "group_names" {
  description = "Keycloak groups created from the Team registry (one per Team)."
  value       = keys(local.teams)
}

output "realm_roles" {
  description = "Developer-access realm roles."
  value       = [for r in keycloak_role.posture : r.name]
}
