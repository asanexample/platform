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

# oauth2-proxy fronting the PREPROD Argo Rollouts web UI (no native auth) with Keycloak OIDC SSO. The Keycloak
# client + secret live on the platform hub; keycloak-config replicates the secret into THIS account's Secrets
# Manager (replicate_client_secrets_to_preprod=["rollouts"]) so the proxy reads it via local ESO. The proxy
# reaches the hub Keycloak over TGW (verified: cross-vpc-dns + 200 on OIDC discovery), so NO host-alias is needed
# (that's a hub-only hairpin workaround). The gateway-config `rollouts` route points at THIS proxy, never the
# dashboard directly.

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The dashboard it fronts is owned by the argo-rollouts unit (enable_dashboard); order after it.
dependency "argo_rollouts" {
  config_path = "../argo-rollouts"

  mock_outputs                            = {}
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
  create    = true
  name      = "rollouts"
  namespace = "argo-rollouts"

  upstream_url = "http://argo-rollouts-dashboard.argo-rollouts.svc:3100"
  external_url = "https://rollouts.preprod.aws.refplat.org"

  # Hub Keycloak issuer (stable canonical URL) + the client minted there; the secret is replicated into THIS
  # account's SM by keycloak-config, so the store is the local one.
  oidc_issuer_url = "https://keycloak.aws.refplat.org/realms/platform"
  oidc_client_id  = "rollouts"
  # The preprod-account replica (keycloak-config replicate_client_secrets_to_preprod), under the `preprod/` prefix
  # so the preprod ESO role can read it.
  oidc_client_secret_sm_key = "preprod/keycloak/rollouts-oidc"
  secret_store_name         = "aws-secrets-manager"

  # No host-alias: the issuer is on the HUB gateway, reached over TGW (not a local hairpin). Verified reachable.
  issuer_host_alias = ""

  tags = include.base.locals.tags
}
