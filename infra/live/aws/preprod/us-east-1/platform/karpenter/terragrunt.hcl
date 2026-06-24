include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.karpenter
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    cluster_security_group_id     = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Karpenter runs on the system node group + reuses its node IAM role; depend on node-groups so both exist.
dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs = {
    node_role_arn = "arn:aws:iam::000000000000:role/mock-node"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    subnet_ids = { "az1-kubernetes" = "subnet-mock" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cilium must be on every node before pods schedule (BYOCNI); eks-addons carries the Pod Identity agent the
# controller authenticates through. Order after both.
dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks_addons" {
  config_path = "../eks-addons"

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
  create       = include.base.locals.enable_karpenter
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  node_role_arn             = dependency.node_groups.outputs.node_role_arn
  cluster_security_group_id = dependency.eks.outputs.cluster_security_group_id
  subnet_ids                = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
  single_az                 = include.base.locals.single_az_nodes
  node_arch                 = include.base.locals.node_arch

  # AGGRESSIVE — preprod runs ephemeral tenant workloads (ArgoCD reschedules on disruption). Spot for cheap +
  # WhenEmptyOrUnderutilized consolidation bin-packs and reclaims, the cost/elasticity win. (ADR-078.)
  capacity_types       = ["spot", "on-demand"]
  consolidation_policy = "WhenEmptyOrUnderutilized"
  consolidate_after    = "1m"
  cpu_limit            = 48
  memory_limit         = "192Gi"
  # Require 8 GiB+ nodes — the per-node DaemonSet slab (Cilium, Beyla, Alloy) exhausts a 4 GiB t4g.medium.
  min_instance_memory_mib = 6144

  high_availability  = include.base.locals.high_availability
  helm_chart_version = include.base.locals.helm_versions.karpenter
  helm_wait          = true

  tags = include.base.locals.tags
}
