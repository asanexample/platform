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

# Dex creates the OIDC client secret at platform/oauth2-proxy/oidc (static_clients = oauth2-proxy).
dependency "dex" {
  config_path = "../dex"

  mock_outputs                            = { namespace = "dex" }
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

  # Split-horizon: resolve the Dex issuer host to the in-cluster gateway so proxy<->Dex traffic never
  # leaves the cluster. Same value as the backstage unit's host_aliases; if the gateway Service ClusterIP
  # changes, update both (dynamic resolution tracked in #195).
  host_aliases = [{
    ip        = "172.20.184.24"
    hostnames = ["sso.aws.refplat.org"]
  }]

  tags = include.base.locals.tags
}
