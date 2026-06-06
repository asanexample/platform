include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.keycloak
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# External Secrets (the ExternalSecret CRD + operator) and secret-stores (the aws-secrets-manager
# ClusterSecretStore) sync the generated admin credential.
dependency "external_secrets" {
  config_path = "../external-secrets"

  mock_outputs                            = { namespace = "external-secrets" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "secret_stores" {
  config_path = "../secret-stores"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# CloudNativePG operator must exist before the Keycloak DB Cluster CR is applied.
dependency "cloudnative_pg" {
  config_path = "../cloudnative-pg"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Foundational shared Gateway (ADR-053/059). Keycloak owns its HTTPRoute on it, so the endpoint is live BEFORE
# keycloak-config (which configures the realm through keycloak.aws.refplat.org). gateway has no app deps, so this
# does not create a cycle.
dependency "gateway" {
  config_path = "../gateway"

  mock_outputs = {
    gateway_name      = "platform-gateway"
    gateway_namespace = "default"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
      }
    }
  EOF
}

generate "kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
      }
    }
  EOF
}

inputs = {
  create = true

  helm_chart_version = include.base.locals.helm_versions.keycloak

  # Deploy-only (B1): Keycloak runs alongside Dex at keycloak.aws.refplat.org. The realm, the Identity Center
  # SAML broker, OIDC clients, and group/role mappers (the access-model-as-code) land in B2; Dex still owns
  # sso.aws.refplat.org until the rebuild cutover. See ADR-053.
  hostname_url = "https://keycloak.aws.refplat.org"

  # Keycloak self-owns its HTTPRoute on the shared Gateway (ADR-059) — so the endpoint is up before keycloak-config.
  create_route      = true
  gateway_name      = dependency.gateway.outputs.gateway_name
  gateway_namespace = dependency.gateway.outputs.gateway_namespace

  tags = include.base.locals.tags
}
