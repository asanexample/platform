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

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Cross-environment: attaches to the TGW hub in the platform account
dependency "platform_tgw" {
  config_path = "../../../../platform/us-east-1/platform/transit-gateway"

  mock_outputs = {
    transit_gateway_id = "tgw-mock"
    ram_share_arn      = "arn:aws:ram:us-east-1:000000000000:resource-share/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create     = true
  name       = "${include.base.locals.env}-${include.base.locals.region_abbv}-tgw"
  create_tgw = false # Spoke mode — attaches to TGW created by platform hub

  transit_gateway_id = dependency.platform_tgw.outputs.transit_gateway_id
  ram_share_arn      = dependency.platform_tgw.outputs.ram_share_arn

  vpc_id = dependency.networking.outputs.vpc_id

  # Filter to transit-tier subnets (/28 per AZ, dedicated to TGW ENIs)
  subnet_ids = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("transit$", name))
  ]

  route_table_ids = dependency.networking.outputs.private_route_table_ids

  # Routes to add to preprod VPC route tables pointing at TGW
  destination_cidrs = ["10.100.0.0/16"] # Platform VPC CIDR

  # Allow inbound traffic from platform VPC through EKS cluster SG
  security_group_id            = dependency.eks.outputs.cluster_security_group_id
  security_group_ingress_cidrs = ["10.100.0.0/16"] # Platform VPC CIDR

  tags = include.base.locals.tags
}
