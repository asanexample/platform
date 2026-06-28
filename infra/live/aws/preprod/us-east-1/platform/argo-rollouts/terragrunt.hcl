include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.argo_rollouts
}

# Argo Rollouts controller + CRDs (ADR-056) — the progressive-delivery control plane. Installed AFTER the shared
# gateway and BEFORE policy: the ADR-085 availability policies match the `Rollout` kind, and a Kyverno rule
# naming a kind with no CRD fails to create (Kyverno #7839), so the CRDs must land first (the `policy` unit
# declares the dependency on this unit). The Gateway-API traffic-router plugin (weighted canary) is wired in a
# later phase.
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "gateway" {
  config_path = "../gateway"

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

inputs = {
  cluster_name       = dependency.eks.outputs.cluster_id
  create             = true
  helm_chart_version = include.base.locals.helm_versions.argo_rollouts
  replica_count      = 1 # non-prod; platform/hub runs 2 for HA
  helm_wait          = true

  # Argo Rollouts web UI (this cluster's rollouts — incl. the tenant app canaries) — exposed Tailscale-only at
  # rollouts.preprod.aws.refplat.org via the gateway-config `rollouts` route.
  enable_dashboard = true
  # The UI hangs on an empty default namespace; default it to a populated one (the demo app's prod). The switcher
  # still reaches the other tenant namespaces. (Brittle if alpha-shop goes away — revisit with a smarter default.)
  dashboard_default_namespace = "alpha-shop-prod"

  tags = include.base.locals.tags
}
