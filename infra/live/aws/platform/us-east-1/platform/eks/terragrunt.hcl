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

  mock_outputs = {
    vpc_id                = "vpc-mock"
    subnet_ids            = {}
    eks_security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "iam_roles" {
  config_path = "../iam-roles"

  mock_outputs = {
    role_arns = {
      PlatformAdmin    = "arn:aws:iam::000000000000:role/PlatformAdmin"
      PlatformDeployer = "arn:aws:iam::000000000000:role/PlatformDeployer"
      DeveloperAccess  = "arn:aws:iam::000000000000:role/DeveloperAccess"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
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
  endpoint_public_access  = false

  eks_addons = {}

  access_entries = {
    platform_admin = {
      principal_arn = dependency.iam_roles.outputs.role_arns["PlatformAdmin"]
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    platform_deployer = {
      principal_arn = dependency.iam_roles.outputs.role_arns["PlatformDeployer"]
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    # developer = {
    #   principal_arn = dependency.iam_roles.outputs.role_arns["DeveloperAccess"]
    #   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
    #   scope_type    = "namespace"
    #   namespaces    = ["team-a"]  # add namespaces here as tenants are onboarded
    # }
    break_glass = {
      principal_arn = "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
  }

  tags = include.base.locals.tags
}
