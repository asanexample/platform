include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.keycloak_config
}

# Configures the running Keycloak (deployed by the keycloak unit) via the keycloak/keycloak provider — B2,
# ADR-053. The provider talks to the LIVE admin API, so this unit is not CI-plan-tested; apply is rebuild-gated
# (and needs Keycloak actually serving + the deployer on Tailscale to reach keycloak.aws.refplat.org).
dependency "keycloak" {
  config_path = "../keycloak"

  mock_outputs = {
    namespace    = "keycloak"
    service_name = "keycloak"
    service_port = 80
    issuer       = "https://keycloak.aws.refplat.org"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The keycloak provider authenticates as the bootstrap admin (admin-cli password grant); creds are in Secrets
# Manager (platform/keycloak/admin), created by the keycloak module. (Hardening follow-up: a dedicated
# terraform service-account client with client_credentials.) The aws provider comes from root.hcl.
generate "keycloak_provider" {
  path      = "keycloak-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "kc_admin" {
      secret_id = "platform/keycloak/admin"
    }

    locals {
      kc_admin = jsondecode(data.aws_secretsmanager_secret_version.kc_admin.secret_string)
    }

    provider "keycloak" {
      url       = "${dependency.keycloak.outputs.issuer}"
      client_id = "admin-cli"
      username  = local.kc_admin.username
      password  = local.kc_admin.password
      realm     = "master"
    }
  EOF
}

inputs = {
  create = true

  keycloak_url = dependency.keycloak.outputs.issuer

  # Identity Center SAML broker. A SEPARATE Identity Center SAML app from Dex's/ArgoCD's (its own signing cert),
  # ACS/audience = https://keycloak.aws.refplat.org/realms/platform/broker/aws-sso/endpoint. Values live in
  # secrets.hcl; saml_ca_data is the BARE base64 cert body (no PEM headers). See docs/runbooks/keycloak-sso.md.
  saml_sso_url = include.base.locals.all_vars.keycloak_sso_url
  saml_ca_data = include.base.locals.all_vars.keycloak_sso_ca_data
}
