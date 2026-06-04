include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.backstage
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

# Orders Backstage after the CloudNativePG operator (the in-cluster DB Cluster CR needs the CRDs + the
# reconciling controller to exist).
dependency "cloudnative_pg" {
  config_path = "../cloudnative-pg"

  mock_outputs = {
    namespace = "cnpg-system"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# OIDC (Phase 2.1): the ExternalSecret needs the operator + ClusterSecretStore, and the client secret
# (platform/backstage/oidc) is created by the dex module — so Backstage applies after all three.
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

dependency "dex" {
  config_path = "../dex"

  mock_outputs                            = { namespace = "dex" }
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

  helm_chart_version = include.base.locals.helm_versions.backstage

  # The signed image built by the asanexample/backstage repo CI (platform/backstage). Bump this SHA +
  # re-apply to roll out a new portal build (Terragrunt-deployed; not GitOps like the tenant apps).
  image_tag = "7557310d980043d27506f1dd6d6b713d2913b306"

  # Split-horizon for OIDC SSO (Phase 2.1): the backend reaches Dex's issuer (sso.aws.refplat.org)
  # in-cluster via the Cilium gateway ClusterIP, not public DNS / the internal-NLB hairpin. The IP is
  # the `cilium-gateway-platform-gateway` Service ClusterIP (default ns) — stable for the Service's life;
  # if that Service is recreated, refresh this. TLS still validates (wildcard *.aws.refplat.org at the gateway).
  host_aliases = [{
    ip        = "172.20.184.24"
    hostnames = ["sso.aws.refplat.org"]
  }]

  # Phase 2.0: in-cluster CloudNativePG (dev). Flip to mode = "rds" (+ rds_host/rds_secret_name) for prod.
  database = {
    mode         = "in-cluster"
    instances    = 1
    storage_size = "5Gi"
  }

  tags = include.base.locals.tags
}
