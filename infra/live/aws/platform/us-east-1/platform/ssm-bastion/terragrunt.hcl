include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.ssm_bastion
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vpc_id     = "vpc-mock"
    subnet_ids = { "kubernetes" = "subnet-mock" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create = true
  name   = "${include.base.locals.env}-${include.base.locals.region_abbv}-ssm-bastion"
  vpc_id = dependency.networking.outputs.vpc_id

  subnet_id = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("kubernetes$", name))
  ][0]

  cluster_security_group_id = dependency.eks.outputs.cluster_security_group_id

  tags = include.base.locals.tags
}
