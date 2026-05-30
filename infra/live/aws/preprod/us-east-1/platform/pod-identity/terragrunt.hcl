include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.eks_pod_identity
}

locals {
  teams_config = read_terragrunt_config("${get_terragrunt_dir()}/../teams.hcl")
  # One Pod Identity association per team that declares AWS access (teams.hcl `aws` block, ADR-041).
  aws_teams = local.teams_config.locals.aws_teams
}

# Cluster name for the associations.
dependency "eks" {
  config_path = "../eks"

  mock_outputs                            = { cluster_id = "mock-cluster" }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The Pod Identity agent add-on must be installed before associations inject credentials.
dependency "eks_addons" {
  config_path = "../eks-addons"

  mock_outputs                            = { addon_arns = {} }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Team namespaces (team-<team>) must exist before binding an association to them.
dependency "tenants" {
  config_path = "../tenants"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Ordering only: the Pod-team-<team> roles must exist (iam-roles) before the association references them.
# The ARN is constructed by convention to avoid a mock-map dependency on iam-roles outputs.
dependency "iam_roles" {
  config_path = "../iam-roles"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  associations = { for t, v in local.aws_teams : t => {
    namespace       = "team-${t}"
    service_account = v.aws.service_account
    role_arn        = "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:role/Pod-team-${t}"
  } }

  tags = include.base.locals.tags
}
