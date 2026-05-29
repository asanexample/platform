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
    role_arns = merge(
      {
        PlatformAdmin    = "arn:aws:iam::000000000000:role/PlatformAdmin"
        PlatformDeployer = "arn:aws:iam::000000000000:role/PlatformDeployer"
        ArgoCD           = "arn:aws:iam::000000000000:role/ArgoCD"
      },
      { for team, _ in local.namespace_teams :
        "DeveloperAccess-${team}" => "arn:aws:iam::000000000000:role/DeveloperAccess-${team}"
      },
    )
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

locals {
  teams_config    = read_terragrunt_config("${get_terragrunt_dir()}/../teams.hcl")
  namespace_teams = local.teams_config.locals.namespace_teams
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
  endpoint_public_access  = true # Public endpoint required — cross-VPC DNS not yet resolving private endpoint

  eks_addons = {} # Managed addons deployed separately in eks-addons unit (BYOCNI ordering)

  access_entries = merge({
    # Read across the cluster (View) + the platform-operator group for debug/operate
    # verbs (cluster-rbac unit). Not cluster-admin: authoring is GitOps-only (ADR-040).
    platform_admin = {
      principal_arn     = dependency.iam_roles.outputs.role_arns["PlatformAdmin"]
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      kubernetes_groups = ["platform-operators"]
    }
    platform_deployer = {
      principal_arn = dependency.iam_roles.outputs.role_arns["PlatformDeployer"]
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    # ArgoCD on the platform cluster assumes this role to manage preprod workloads
    argocd = {
      principal_arn = dependency.iam_roles.outputs.role_arns["ArgoCD"]
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    break_glass = {
      principal_arn = "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    },
    # One group-mapped access entry per namespace team (Bridge B): maps the team's
    # DeveloperAccess-<team> role to the Kubernetes group team-<team>:developers.
    # Authorization is governed by the namespace-scoped RoleBinding the tenant
    # module creates for that group — not by an AWS-managed access policy.
    { for team, _ in local.namespace_teams :
      "developer_${team}" => {
        principal_arn     = dependency.iam_roles.outputs.role_arns["DeveloperAccess-${team}"]
        type              = "STANDARD"
        kubernetes_groups = ["team-${team}:developers"]
      }
  })

  tags = include.base.locals.tags
}
