include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.networking
}

inputs = {
  create        = false # Prod networking not yet deployed
  vpc_name      = "${include.base.locals.env}-${include.base.locals.region_abbv}-vpc"
  address_space = include.base.locals.all_vars.address_space
  subnets       = include.base.locals.all_vars.subnets
  environment   = include.base.locals.env
  workload      = include.base.locals.workload
  region_abbv   = include.base.locals.region_abbv
  tags          = include.base.locals.tags

  create_internet_gateway = true
  create_nat_gateways     = true
  single_nat_gateway      = false # One NAT per AZ for HA (unlike preprod which uses a single NAT)

  enable_eks_networking = true
  eks_cluster_name      = "${include.base.locals.env}-${include.base.locals.region_abbv}-eks"

  enable_flow_logs        = true
  flow_log_retention_days = 90 # Longer retention than preprod (30d) for compliance
}
