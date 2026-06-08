include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.oauth2_proxy
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

# External Secrets operator (ExternalSecret CRD) + the aws-secrets-manager ClusterSecretStore — both
# needed to sync the client-secret (and cookie-secret) into the backstage namespace.
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

# keycloak-config registers the `oauth2-proxy` OIDC client + writes its secret to
# platform/keycloak/oauth2-proxy-oidc (B4 cutover — Keycloak is the IdP of record, ADR-053/059). Order after it.
dependency "keycloak_config" {
  config_path = "../keycloak-config"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Backstage owns the namespace and is the upstream this proxy fronts. Order after it.
dependency "backstage" {
  config_path = "../backstage"

  mock_outputs                            = { namespace = "backstage", service_name = "backstage", service_port = 7007 }
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

  helm_chart_version = include.base.locals.helm_versions.oauth2_proxy

  namespace = dependency.backstage.outputs.namespace

  # B4 cutover: front Backstage with Keycloak (the IdP of record), not Dex. Issuer + client/secret come from the
  # keycloak-config `oauth2-proxy` client; the module's oidc_client_id ("oauth2-proxy") + client_secret_key
  # ("client-secret") defaults already match Keycloak.
  oidc_issuer_url    = "https://keycloak.aws.refplat.org/realms/platform"
  client_secret_name = "platform/keycloak/oauth2-proxy-oidc"

  # Split-horizon: resolve the issuer host to the in-cluster gateway ClusterIP so proxy<->Keycloak traffic never
  # leaves the cluster (avoids the internal-NLB hairpin). NOTE: this ClusterIP is hardcoded and CHANGES every
  # rebuild — update it (and the backstage unit's) to the current `cilium-gateway-platform-gateway` ClusterIP
  # after each rebuild until dynamic resolution lands (#195).
  host_aliases = [{
    ip        = "172.20.31.49"
    hostnames = ["keycloak.aws.refplat.org"]
  }]

  tags = include.base.locals.tags
}
