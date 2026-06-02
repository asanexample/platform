include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.policy
}

locals {
  # The platform cluster hosts shared services, not tenants — there is no teams.hcl here. The engine,
  # cluster-scoped hardening (RBAC, default-namespace), and the registry floor still apply.
  ecr_registry = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"
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
  create = true

  # Enforce: webhook fails closed. Flipped after preprod was proven in Enforce and the cluster-scoped
  # RBAC policies were hardened to exempt the IaC deployer (validated on preprod: PlatformDeployer
  # cluster-admin binding denied -> admitted). ArgoCD + the deployer (the RBAC-creating actors here)
  # are in exclude_principals. See ADR-014 / kyverno-break-glass runbook.
  validation_failure_action = "Enforce"

  compliance_tier = include.base.locals.compliance_tier
  replica_count   = 3 # HA on the shared platform cluster

  # Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod IPs,
  # so the admission/cleanup webhook servers must run on hostNetwork (node VPC IP). Applied AFTER
  # the overlay cutover (hostNetwork needs the overlay cilium's kubeProxyReplacement to reach the apiserver).
  webhook_host_network = true

  allowed_registries  = [local.ecr_registry]
  tenant_registry_map = {} # no tenants on the platform cluster

  helm_chart_version = include.base.locals.helm_versions.kyverno
  helm_wait          = true

  tags = include.base.locals.tags
}
