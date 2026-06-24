include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.organizations
}

inputs = {
  create              = true
  create_organization = true
  tags                = include.base.locals.tags
  allowed_regions     = ["us-east-1", "us-west-2"]
  required_tags       = ["Environment", "ManagedBy", "Owner"]
  # crossplane-ecr-provisioner (platform) Team-tags tenant ECR repos; crossplane-provisioner-* (per workload
  # cluster) Team-tags the Pod-team IAM roles it creates — both need the DenyTeamTagTampering exemption (BACK
  # stack P2b / ADR-048). A wildcard covers preprod now + prod later.
  # Karpenter node-provisioner controllers (ADR-078): like the EKS/ASG service roles + crossplane provisioners
  # they must set governance tags on the resources they create (tags via the launch template, not the
  # RunInstances request) — exempt from DenyTeamTagTampering + require-tagging. ANCHORED per-cluster
  # (`<cluster>-karpenter-*`, the module's name_prefix) instead of a leading-wildcard `*-karpenter-*`, so an
  # unrelated role merely containing "-karpenter-" can't inherit the exemption (security audit).
  exempt_roles = [
    "OrganizationAccountAccessRole", "github-actions-terratest", "PlatformDeployer",
    "crossplane-ecr-provisioner", "crossplane-provisioner-*",
    "platform-use1-eks-karpenter-*", "preprod-use1-eks-karpenter-*",
  ]

  # Close the OU-coverage gap (security audit): the Platform OU (which holds the Platform + Test accounts) only
  # got `protect-data-and-network`, so `require-tagging` + `restrict-iam-users` (no IAM users / force federation)
  # did not cover the most-privileged account. Attach them there too — matching the Workloads OU. The IaC roles
  # (PlatformDeployer, github-actions-terratest) are already in `exempt_roles`, so applies aren't blocked.
  scp_attachments = {
    "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Platform"  = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
    "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
  }

  organizational_units = {
    "Platform"            = { parent = null }
    "Workloads"           = { parent = null }
    "Workloads/Preprod"   = { parent = "Workloads" }
    "Workloads/Prod"      = { parent = "Workloads" }
    "Workloads/Regulated" = { parent = "Workloads" }
  }

  accounts = {
    "Platform" = { email = include.base.locals.account_emails["platform"], ou = "Platform" }
    "Test"     = { email = include.base.locals.account_emails["test"], ou = "Platform" }
    "Preprod"  = { email = include.base.locals.account_emails["preprod"], ou = "Workloads/Preprod" }
    "Prod"     = { email = include.base.locals.account_emails["prod"], ou = "Workloads/Prod" }
  }
}
