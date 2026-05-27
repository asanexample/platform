include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.transit_gateway
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vpc_id                  = "vpc-mock"
    subnet_ids              = {}
    private_route_table_ids = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create     = true
  name       = "${include.base.locals.env}-${include.base.locals.region_abbv}-tgw"
  create_tgw = true

  ram_share_principals = ["620830101009"]

  vpc_id = dependency.networking.outputs.vpc_id

  subnet_ids = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("transit$", name))
  ]

  route_table_ids = dependency.networking.outputs.private_route_table_ids

  destination_cidrs = ["10.101.0.0/16"]

  tags = include.base.locals.tags
}
