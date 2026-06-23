include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_pyroscope_ebpf
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

# Writes profiles to the Pyroscope store — order after it so the endpoint exists.
dependency "pyroscope" {
  config_path = "../pyroscope"

  mock_outputs = {
    namespace = "observability"
    query_url = "http://pyroscope.observability.svc:4040"
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

inputs = {
  # Pairs with the Pyroscope store (enable_pyroscope). create=false applies as a no-op.
  create    = include.base.locals.enable_pyroscope
  namespace = dependency.pyroscope.outputs.namespace

  helm_chart_version = include.base.locals.helm_versions.alloy

  # Profiles → the hub Pyroscope under this cluster's tenant.
  pyroscope_url = dependency.pyroscope.outputs.query_url
  tenant_id     = include.base.locals.env

  tags = include.base.locals.tags
}
