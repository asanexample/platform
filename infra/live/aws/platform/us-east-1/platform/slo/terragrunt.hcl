include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_slo
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

# SLOs evaluate against metrics in the hub Prometheus + render dashboards via the observability Grafana
# sidecar. Depend on observability so the namespace exists and the rule/dashboard discovery is in place.
dependency "observability" {
  config_path = "../observability"

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
  namespace = dependency.observability.outputs.namespace

  helm_chart_version = include.base.locals.helm_versions.sloth

  # SLO dashboard (14643) queries the hub Mimir (where the SLI/burn-rate recording rules land).
  slo_dashboard_datasource_uid = "mimir"

  # First SLO: API server request availability — the one control-plane signal EKS exposes, always has
  # traffic. Sloth fills {{.window}} per burn-rate window. Burn-rate alerts route via the P4 Alertmanager.
  slos = [{
    name        = "kubernetes-apiserver"
    service     = "kubernetes-apiserver"
    slo_name    = "requests-availability"
    description = "API server request availability (non-5xx responses)."
    objective   = 99.9
    error_query = "sum(rate(apiserver_request_total{code=~\"5..\"}[{{.window}}]))"
    total_query = "sum(rate(apiserver_request_total[{{.window}}]))"
    alert_name  = "K8sApiserverAvailability"
  }]

  tags = include.base.locals.tags
}
