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
