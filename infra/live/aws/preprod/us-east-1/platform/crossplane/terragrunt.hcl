include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.crossplane
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Ordering only: Crossplane's rbac-manager authors wildcard provider ClusterRoles at runtime that the
# preprod Kyverno (Enforce) restrict-wildcard-rbac policy would deny unless crossplane-system is excluded.
# The policy unit carries that exclusion (extra_exclude_principals/namespaces), so it must apply first.
dependency "policy" {
  config_path = "../policy"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
      }
    }
  EOF
}

inputs = {
  create = true

  cluster_name = dependency.eks.outputs.cluster_id
  region       = include.base.locals.region
  account_id   = include.base.locals.account_id # preprod — unused until AWS providers land (P2b)

  helm_chart_version = include.base.locals.helm_versions.crossplane
  helm_wait          = true

  # Federated tenant control plane (ADR-048). P2b: the full tenant footprint — K8s (provider-kubernetes) +
  # AWS (provider-aws iam/eks locally; ecr cross-account into the platform account via assumeRoleChain).
  provider_services = ["ecr", "iam", "eks"]

  enable_kubernetes_provider = true
  # provider-kubernetes stays hostNetwork + list index 0 (its P2a config) so it does NOT churn when the aws
  # providers are added — keeping it on its current node where its (hardcoded :8080/:8081/9443) ports are
  # free. Its Object conversion webhook needs hostNetwork to be apiserver-reachable under the overlay.
  kubernetes_provider_hostnetwork = true

  functions = [
    { name = "function-go-templating", package = "xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.12.1" },
    { name = "function-auto-ready", package = "xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.6.5" },
    { name = "function-environment-configs", package = "xpkg.upbound.io/crossplane-contrib/function-environment-configs:v0.7.1" },
  ]

  enable_tenant_api = true

  # ArgoCD delivers the XTenant claims (tenant-claims-preprod app) from the platform cluster, authenticating to
  # this remote cluster via the cross-account `ArgoCD` IAM role — so its admission username is that role's
  # assumed-role ARN, not the in-cluster argocd SA. Allow it past restrict-tenant-control-plane (ADR-046/048).
  # Scoped to THIS (preprod) account; the `ArgoCD` role + EKS access entry are platform-owned.
  tenant_policy_values = {
    extraExcludePrincipals = ["arn:aws:sts::${include.base.locals.account_ids["preprod"]}:assumed-role/ArgoCD/*"]
  }

  # Tenant provisioning identity (P2b): scoped IAM + EKS Pod Identity locally, plus assume the platform ECR
  # role for cross-account repos. The deny-escalation permissions boundary is created in the module.
  enable_tenant_provisioning = true
  ecr_provisioner_role_arn   = "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/crossplane-ecr-provisioner"

  # Cluster constants for the Composition's EnvironmentConfig: platform ECR registry + cross-account pull.
  ecr_registry            = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"
  tenant_pull_account_ids = [include.base.locals.account_ids["preprod"], include.base.locals.account_ids["prod"]]

  # Tenant app ingress domain — the Composition derives each app's allowed route hostnames as
  # <app>-<team>.<base_domain> + the <app>-<team>-pr-* preview wildcard (ADR-060). Matches the argocd-apps
  # preview_domain (which injects the actual route hostnames from the same convention).
  base_domain = "preprod.aws.refplat.org"

  # Management account ID — the Composition's DeveloperAccess-<team> trust allows the per-team SSO permission
  # set (Dev-<team>) in both the management and preprod accounts to assume the role (P2c, ADR-039).
  management_account_id = include.base.locals.account_ids["mgmt"]

  # Team CRs are now git-native (ADR-063): authored as YAML in gitops/teams/ and ArgoCD-synced (the `teams` app
  # in the argocd-apps unit). The crossplane-teams Helm projection is therefore disabled — teams = {} renders no
  # Team CRs — while the Team CRD itself still ships with the tenant chart (enable_tenant_api). Source of truth
  # for the envelope Kyverno reads is the git-synced Team CR, not this module.
  teams = {}

  # Destroy-time CR finalizer cleanup auth (scripts/k8s-finalizer-clear.sh) — see crd_finalizer_cleanup.
  deployer_role_arn      = include.base.locals.deployer_role_arn
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"

  tags = include.base.locals.tags
}
