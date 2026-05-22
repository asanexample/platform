# Centralized version pins for AWS modules and Helm charts.
# Environments can override these by defining their own _versions.hcl at the env level.
#
# VERSIONING STRATEGY:
# - Monorepo (current): modules are sourced from get_repo_root() at HEAD.
#   All environments share the same module code. Safe for small teams.
# - Registry (future): change source_base to a Terraform registry URL and
#   pin each module to a semver tag. Enables independent env promotion.

locals {
  source_base = "${get_repo_root()}/infra/modules"

  module_source = {
    # Core infrastructure
    networking = "${local.source_base}/aws//networking"
    naming     = "${local.source_base}/aws//naming"

    # Compute
    eks            = "${local.source_base}/aws//eks"
    eks_addons     = "${local.source_base}/aws//eks-addons"
    eks_node_group = "${local.source_base}/aws//eks-node-group"
    ssm_bastion    = "${local.source_base}/aws//ssm-bastion"

    # IAM
    iam_roles = "${local.source_base}/aws//iam_roles"

    # Storage & secrets
    kms = "${local.source_base}/aws//kms"
    ecr = "${local.source_base}/aws//ecr"

    # Observability
    cloudwatch        = "${local.source_base}/aws//cloudwatch"
    prometheus        = "${local.source_base}/aws//prometheus"
    grafana           = "${local.source_base}/aws//grafana"
    cloudwatch_alarms = "${local.source_base}/aws//cloudwatch_alarms"

    # DNS
    route53        = "${local.source_base}/aws//route53"
    dns_delegation = "${local.source_base}/cloudflare//dns_delegation"

    # CI/CD
    github_oidc = "${local.source_base}/aws//github_oidc"

    # Governance & compliance
    organizations   = "${local.source_base}/aws//organizations"
    identity_center = "${local.source_base}/aws//identity_center"
    cloudtrail      = "${local.source_base}/aws//cloudtrail"
    budgets         = "${local.source_base}/aws//budgets"
    state_bootstrap = "${local.source_base}/aws//state_bootstrap"

    # Cloud-agnostic (Kubernetes add-ons)
    cilium           = "${local.source_base}/cilium"
    argocd           = "${local.source_base}/argocd"
    argocd_bootstrap = "${local.source_base}/argocd-bootstrap"
    cert_manager     = "${local.source_base}/cert-manager"
    external_dns     = "${local.source_base}/external-dns"
    external_secrets = "${local.source_base}/external-secrets"
    gateway_config   = "${local.source_base}/gateway-config"
    tailscale        = "${local.source_base}/tailscale"
    policy           = "${local.source_base}/policy"
  }

  # Helm chart version pins — single source of truth across environments
  helm_versions = {
    cilium             = "1.17.2"
    argocd             = "9.5.14"
    cert_manager       = "1.17.1"
    external_dns       = "1.16.1"
    external_secrets   = "0.14.3"
    kyverno            = "3.3.7"
    tailscale_operator = "1.96.5"
  }
}
