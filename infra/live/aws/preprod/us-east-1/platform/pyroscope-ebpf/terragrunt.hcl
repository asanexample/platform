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

# The eBPF profiler (privileged PSA) runs in the shared observability namespace owned by the metrics spoke.
dependency "observability_spoke" {
  config_path = "../observability-spoke"

  mock_outputs = {
    namespace = "observability"
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
  # Pairs with the preprod eBPF instrumentation (Beyla) toggle. create=false applies as a no-op.
  create    = include.base.locals.enable_instrumentation
  namespace = dependency.observability_spoke.outputs.namespace

  helm_chart_version = include.base.locals.helm_versions.alloy

  # Profiles → the hub Pyroscope via its write-only Gateway edge. The edge force-stamps X-Scope-OrgID=preprod
  # (the spoofing guard), so preprod profiles land under the `preprod` tenant alongside its Beyla traces —
  # lighting up the trace→flame-graph correlation for the alpha apps.
  pyroscope_url = "https://preprod-profiles.aws.refplat.org"
  tenant_id     = include.base.locals.env
}
