include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.eks_node_group
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    subnet_ids = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id = "mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "cilium" {
  config_path = "../cilium"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  node_groups = {
    system = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = ["t3.large"]
      desired_size   = 2
      max_size       = 4
      min_size       = 2
      labels         = { "node-role" = "system" }
    }
    workload = {
      subnet_ids     = [for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))]
      instance_types = ["t3.large"]
      desired_size   = 1
      max_size       = 6
      min_size       = 1
      labels         = { "node-role" = "workload" }
    }
  }

  tags = include.base.locals.tags
}
