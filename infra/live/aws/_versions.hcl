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
    ecr      = "${local.source_base}/aws//ecr"
    s3       = "${local.source_base}/aws//s3"
    sops_kms = "${local.source_base}/aws//sops-kms" # SOPS config-encryption key (ADR-066)

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
    gateway             = "${local.source_base}/gateway"
    gateway_config      = "${local.source_base}/gateway-config"
    cluster_rbac        = "${local.source_base}//cluster-rbac"
    policy              = "${local.source_base}//policy"
    tailscale           = "${local.source_base}/tailscale"
    tailscale_admin     = "${local.source_base}/tailscale-admin"
    falco               = "${local.source_base}/falco"
    observability       = "${local.source_base}/observability"
    observability_mimir = "${local.source_base}/observability-mimir"
    observability_loki  = "${local.source_base}/observability-loki"
    observability_alloy = "${local.source_base}/observability-alloy"
    crossplane          = "${local.source_base}/crossplane"
    cloudnative_pg      = "${local.source_base}/cloudnative-pg"
    backstage           = "${local.source_base}/backstage"
    keycloak            = "${local.source_base}/keycloak"
    keycloak_config     = "${local.source_base}/keycloak-config"
    github_teams        = "${local.source_base}/github-teams"

    actions_runner_controller = "${local.source_base}/actions-runner-controller"
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
    loki                  = "7.0.0"  # grafana/loki — P3a logs store (latest stable, resolved 2026-06-19)
    alloy                 = "1.10.0" # grafana/alloy — P3a log-collector DaemonSet
    crossplane            = "2.3.1"  # Crossplane v2 (ADR-046)
    cloudnative_pg        = "0.28.2" # CNPG operator chart (app v1.29.1) — Backstage DB (ADR-051)
    backstage             = "2.8.1"  # official backstage Helm chart (points at our platform/backstage image)
    keycloak              = "7.2.0"  # codecentric/keycloakx chart; Keycloak 26.6.3 via image-tag override — app IdP (ADR-053, B1)
    arc_controller        = "0.14.2" # gha-runner-scale-set-controller (ADR-065 / #323)
    arc_runner_set        = "0.14.2" # gha-runner-scale-set — pinned in lockstep with the controller
  }
}
