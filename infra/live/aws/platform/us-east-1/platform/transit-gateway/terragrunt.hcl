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

dependency "preprod_eks" {
  config_path = "../../../../preprod/us-east-1/platform/eks"

  mock_outputs = {
    cluster_endpoint = "https://mock.gr7.us-east-1.eks.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "preprod_networking" {
  config_path = "../../../../preprod/us-east-1/platform/networking"

  mock_outputs = {
    vpc_id = "vpc-mock-preprod"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "dns_association" {
  path      = "dns-association.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      alias  = "preprod"
      region = "us-east-1"

      assume_role {
        role_arn = "arn:aws:iam::620830101009:role/PlatformDeployer"
      }
    }

    data "aws_route53_zone" "preprod_eks" {
      provider = aws.preprod

      name         = replace("${dependency.preprod_eks.outputs.cluster_endpoint}", "https://", "")
      private_zone = true
      vpc_id       = "${dependency.preprod_networking.outputs.vpc_id}"
    }

    resource "aws_route53_vpc_association_authorization" "preprod_eks" {
      provider = aws.preprod

      zone_id = data.aws_route53_zone.preprod_eks.zone_id
      vpc_id  = "${dependency.networking.outputs.vpc_id}"
    }

    resource "aws_route53_zone_association" "preprod_eks" {
      zone_id = data.aws_route53_zone.preprod_eks.zone_id
      vpc_id  = "${dependency.networking.outputs.vpc_id}"

      depends_on = [aws_route53_vpc_association_authorization.preprod_eks]
    }
  EOF
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
