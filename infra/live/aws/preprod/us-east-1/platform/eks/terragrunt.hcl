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
      ArgoCD           = "arn:aws:iam::000000000000:role/ArgoCD"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}


inputs = {
  create       = true
  cluster_name = "${include.base.locals.env}-${include.base.locals.region_abbv}-eks"

  # Control-plane logging is OFF in dev (vended audit/api logs ran ~$700/mo across the dev clusters). Re-enable
  # per-env via control_plane_log_types in env.hcl (see _base.hcl). Empty = no vended logs.
  enabled_cluster_log_types = include.base.locals.control_plane_log_types

  subnet_ids = [
    for name, id in dependency.networking.outputs.subnet_ids :
    id if can(regex("kubernetes$", name))
  ]

  additional_security_group_ids = compact([
    dependency.networking.outputs.eks_security_group_id,
  ])

  endpoint_private_access = true
  endpoint_public_access  = false # Private-only (matches platform, ADR-010). Reach via preprod Tailscale (operators) or TGW + cross-vpc-dns (ArgoCD on platform).

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
    # Backstage on the platform cluster assumes this role for READ-ONLY live cluster view (Kubernetes
    # plugin, 2.4a). View, not ClusterAdmin — the portal only reads; AmazonEKSViewPolicy excludes Secrets.
    # The `backstage-readers` group maps to the backstage-read-tenant-api ClusterRole (tenant-policies chart)
    # for reading XTenant status — the provisioning-status card + notifier (#285); AmazonEKSViewPolicy is an
    # EKS-managed authorizer that doesn't cover custom resources, so the group binding adds them on top.
    backstage = {
      principal_arn     = dependency.iam_roles.outputs.role_arns["Backstage"]
      policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
      kubernetes_groups = ["backstage-readers"]
    }
    break_glass = {
      principal_arn = "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole"
      policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    }
    # Per-team developer access entries (DeveloperAccess-<team> → team-<team>:developers) are now provisioned
    # by the Tenant Composition (eks.aws.upbound.io AccessEntry), not here — all teams migrated (BACK stack P3).
  })

  tags = include.base.locals.tags
}
