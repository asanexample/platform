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
    networking      = "${local.source_base}/aws//networking"
    transit_gateway = "${local.source_base}/aws//transit-gateway"

    # Compute
    eks            = "${local.source_base}/aws//eks"
    eks_addons     = "${local.source_base}/aws//eks-addons"
    eks_node_group = "${local.source_base}/aws//eks-node-group"
    ssm_bastion    = "${local.source_base}/aws//ssm-bastion"

    # IAM
    iam_roles        = "${local.source_base}/aws//iam_roles"
    eks_pod_identity = "${local.source_base}/aws//eks-pod-identity"

    # Storage & secrets
    ecr = "${local.source_base}/aws//ecr"
    s3  = "${local.source_base}/aws//s3"

    # Notifications
    sns_notifications = "${local.source_base}/aws//sns-notifications"

    # DNS
    route53            = "${local.source_base}/aws//route53"
    route53_delegation = "${local.source_base}/aws//route53_delegation"
    cross_vpc_dns      = "${local.source_base}/aws//cross-vpc-dns"
    dns_delegation     = "${local.source_base}/cloudflare//dns_delegation"

    # CI/CD
    github_oidc = "${local.source_base}/aws//github_oidc"

    # Governance & compliance
    organizations   = "${local.source_base}/aws//organizations"
    identity_center = "${local.source_base}/aws//identity_center"
    cloudtrail      = "${local.source_base}/aws//cloudtrail"
    state_bootstrap = "${local.source_base}/aws//state_bootstrap"

    # Cloud-agnostic (Kubernetes add-ons)
    cilium              = "${local.source_base}/cilium"
    argocd              = "${local.source_base}/argocd"
    argocd_clusters     = "${local.source_base}/argocd-clusters"
    argocd_apps         = "${local.source_base}/argocd-apps"
    cert_manager        = "${local.source_base}/cert-manager"
    external_dns        = "${local.source_base}/external-dns"
    external_secrets    = "${local.source_base}/external-secrets"
    secret_stores       = "${local.source_base}/secret-stores"
    gateway_config      = "${local.source_base}/gateway-config"
    cluster_rbac        = "${local.source_base}//cluster-rbac"
    tenant              = "${local.source_base}//tenant"
    policy              = "${local.source_base}//policy"
    tailscale           = "${local.source_base}/tailscale"
    tailscale_admin     = "${local.source_base}/tailscale-admin"
    falco               = "${local.source_base}/falco"
    observability       = "${local.source_base}/observability"
    observability_mimir = "${local.source_base}/observability-mimir"
  }

  # Helm chart version pins — single source of truth across environments
  helm_versions = {
    cilium                = "1.19.4"
    argocd                = "9.5.14"
    cert_manager          = "1.17.1"
    external_dns          = "1.16.1"
    external_secrets      = "0.14.3"
    kyverno               = "3.8.1"
    tailscale_operator    = "1.96.5"
    falco                 = "9.0.0"
    kube_prometheus_stack = "86.1.0"
    mimir                 = "6.0.6"
  }
}
