include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cross_vpc_dns
}

dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vpc_id     = "vpc-mock"
    subnet_ids = {}
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "preprod_eks" {
  config_path = "../../../../preprod/us-east-1/platform/eks"

  mock_outputs = {
    cluster_endpoint = "https://mock.gr7.us-east-1.eks.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Uncomment when switching to resolver_outbound mode:
# dependency "preprod_dns" {
#   config_path = "../../../../preprod/us-east-1/platform/cross-vpc-dns"
#   mock_outputs = { resolver_inbound_ips = {} }
#   mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
# }

inputs = {
  create     = true
  name       = "${include.base.locals.env}-${include.base.locals.region_abbv}-dns"
  dns_method = "phz"
  vpc_id     = dependency.networking.outputs.vpc_id

  phz_records = {
    preprod-eks = {
      domain = replace(dependency.preprod_eks.outputs.cluster_endpoint, "https://", "")
      ips    = ["10.101.0.54", "10.101.2.52"]
    }
  }

  tags = include.base.locals.tags
}
