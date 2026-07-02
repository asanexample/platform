include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_opencost
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

# Deploys into the shared observability namespace and queries the kube-prometheus-stack Prometheus there.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cross-account: the CUR/Athena infra lives in the mgmt (payer) account (#668).
dependency "cost_export" {
  config_path = "../../../../mgmt/global/cost-export"

  mock_outputs = {
    cost_reader_role_arn    = "arn:aws:iam::111111111111:role/mock-cost-reader"
    glue_database_name      = "mock_cur"
    athena_workgroup_name   = "mock-workgroup"
    athena_results_location = "s3://mock-bucket/athena-results/"
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

# Kubernetes provider — for the cost dashboard ConfigMap (ADR-091); the helm provider above can't create it.
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
  # Cost-profile toggle (enable_cost_metrics): off in dev by default, on for the platform cluster (env.hcl).
  create = include.base.locals.enable_cost_metrics

  namespace            = dependency.observability.outputs.namespace
  prometheus_service   = "kube-prometheus-stack-prometheus"
  prometheus_namespace = dependency.observability.outputs.namespace

  # Cost dashboard queries the FEDERATED Mimir datasource (tenants platform|preprod) so it shows BOTH the
  # platform-team cost AND the tenant-environment cost emitted by the preprod OpenCost spoke (ADR-091).
  dashboard_datasource_uid = "mimir-all"

  helm_chart_version = include.base.locals.helm_versions.opencost

  # True cloud cost — CUR via Athena, cross-account (#668 Phase 2a/3). Platform-hub-only: the CUR is
  # org-wide (covers preprod's spend too), so there's no need for a second consumer on the preprod spoke.
  enable_cloud_cost         = true
  cluster_name              = dependency.eks.outputs.cluster_id
  cost_reader_role_arn      = dependency.cost_export.outputs.cost_reader_role_arn
  cur_athena_results_bucket = dependency.cost_export.outputs.athena_results_location
  cur_athena_database       = dependency.cost_export.outputs.glue_database_name
  cur_athena_table          = "platform_cur" # crawler-discovered, confirmed via the Glue catalog (docs/runbooks/cost-true-spend.md)
  cur_athena_workgroup      = dependency.cost_export.outputs.athena_workgroup_name
  cur_account_id            = include.base.locals.account_ids["mgmt"]

  tags = include.base.locals.tags
}
