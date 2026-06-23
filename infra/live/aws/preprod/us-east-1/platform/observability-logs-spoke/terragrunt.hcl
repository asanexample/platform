include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_alloy
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

# The metrics spoke owns the preprod `observability` namespace (PSA privileged + default-deny). Order after it
# so the namespace exists before this Alloy DaemonSet schedules into it.
dependency "observability_spoke" {
  config_path = "../observability-spoke"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Logs ship over the Transit Gateway to the platform hub. Order after the TGW spoke attachment.
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

inputs = {
  create    = true
  namespace = dependency.observability_spoke.outputs.namespace

  # Ship to the platform hub's Loki spoke-ingest edge. The hub Gateway force-sets X-Scope-OrgID=preprod
  # per-hostname (write-only), reached privately over the TGW. tenant_id here is belt-and-suspenders (the
  # edge overwrites it anyway); external_labels stamp cluster=preprod so the hub isolates/breaks out by cluster.
  loki_push_url   = "https://preprod-logs.aws.refplat.org/loki/api/v1/push"
  tenant_id       = "preprod"
  external_labels = { cluster = "preprod" }

  helm_chart_version = include.base.locals.helm_versions.alloy
  # DaemonSet on capacity-tight nodes: don't gate the apply on full scheduling (verify readiness out-of-band).
  helm_wait = false

  tags = include.base.locals.tags
}
