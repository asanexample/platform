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
}

dependency "eks" {
  config_path = "../eks"
}

dependency "cilium" {
  config_path = "../cilium"
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
      desired_size   = 2
      max_size       = 6
      min_size       = 1
      labels         = { "node-role" = "workload" }
    }
  }

  tags = include.base.locals.tags
}
