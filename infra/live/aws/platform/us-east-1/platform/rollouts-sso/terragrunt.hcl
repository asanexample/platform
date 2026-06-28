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

# oauth2-proxy fronting the Argo Rollouts web UI (no native auth) with Keycloak OIDC SSO. Runs in the
# argo-rollouts namespace so it reaches the dashboard Service in-cluster; the gateway-config `rollouts` route
# points at THIS proxy (Service `rollouts`), never the dashboard directly. Hub-cluster: the issuer host is pinned
# to the gateway Envoy ClusterIP (split-horizon) so the proxy's backend OIDC calls don't hairpin the internal NLB.

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The OIDC client + its Secrets Manager secret are minted by keycloak-config; depend on it for the issuer URL
# and the client's SM key.
dependency "keycloak_config" {
  config_path = "../keycloak-config"

  mock_outputs = {
    issuer              = "https://keycloak.aws.refplat.org/realms/platform"
    client_secret_names = { rollouts = "platform/keycloak/rollouts-oidc" }
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
  external_url = "https://rollouts.aws.refplat.org"

  oidc_issuer_url           = dependency.keycloak_config.outputs.issuer
  oidc_client_id            = "rollouts"
  oidc_client_secret_sm_key = dependency.keycloak_config.outputs.client_secret_names["rollouts"]
  secret_store_name         = "aws-secrets-manager"

  # Hub cluster: Keycloak is served by THIS cluster's gateway — pin its host to the Envoy ClusterIP to avoid the
  # internal-NLB hairpin (the proxy's backend token/JWKS calls). Spokes reaching the hub issuer over TGW omit this.
  issuer_host_alias         = "keycloak.aws.refplat.org"
  gateway_service_name      = "cilium-gateway-platform-gateway"
  gateway_service_namespace = "default"

  tags = include.base.locals.tags
}
