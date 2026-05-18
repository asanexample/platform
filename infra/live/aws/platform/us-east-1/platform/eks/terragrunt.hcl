include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.eks
}

dependency "networking" {
  config_path = "../networking"
}

inputs = {
  create       = true
  cluster_name = "${include.base.locals.env}-${include.base.locals.region_abbv}-eks"

  subnet_ids = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("kubernetes$", name))
  ]

  additional_security_group_ids = compact([
    dependency.networking.outputs.eks_security_group_id,
  ])

  endpoint_private_access = true
  endpoint_public_access  = true

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

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }

  tags = include.base.locals.tags
}
