include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_prom_agent
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

# The agent ships over Transit Gateway to the platform hub (private). Order after the TGW spoke attachment
# so the cross-VPC route to the hub VPC exists before remote_write starts.
dependency "transit_gateway" {
  config_path = "../transit-gateway"

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
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  # Stamped on every series so the hub isolates preprod under its tenant (`up{cluster="preprod"}`).
  cluster_label = "preprod"

  # Ship to the platform hub's Mimir spoke-ingest edge. The hub Gateway force-sets X-Scope-OrgID=preprod
  # per-hostname (write-only), so no tenant header is sent from here. Reached privately over the TGW.
  remote_write_url = "https://preprod-mimir.aws.refplat.org/api/v1/push"

  helm_chart_version = include.base.locals.helm_versions.kube_prometheus_stack
  helm_wait          = true

  # Sizing follows cost_profile (dev = single replica; prod = HA).
  high_availability = include.base.locals.high_availability
  # WAL on emptyDir (module default): preprod has no gp3 StorageClass, and an ephemeral WAL is fine for a
  # lightweight spoke (the agent re-scrapes on restart). Set to an existing class for a durable WAL.

  tags = include.base.locals.tags
}
