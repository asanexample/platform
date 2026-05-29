include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.route53_delegation
}

dependency "route53" {
  config_path = "../route53"

  mock_outputs = {
    zone_id = "MOCK"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "preprod_route53" {
  config_path = "../../../../preprod/us-east-1/platform/route53"

  mock_outputs = {
    name_servers = ["ns-mock.awsdns-01.com.", "ns-mock.awsdns-02.net."]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create         = true
  parent_zone_id = dependency.route53.outputs.zone_id

  delegations = {
    "preprod.aws.refplat.org" = dependency.preprod_route53.outputs.name_servers
  }
}
