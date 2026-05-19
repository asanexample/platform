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
}

inputs = {
  create = true
  name   = "${include.base.locals.env}-${include.base.locals.region_abbv}-ssm-bastion"
  vpc_id = dependency.networking.outputs.vpc_id

  subnet_id = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("kubernetes$", name))
  ][0]

  tags = include.base.locals.tags
}
