# Centralized version pins for Azure modules and Helm charts.
# Environments can override these by defining their own _versions.hcl at the env level.
#
# VERSIONING STRATEGY:
# - Monorepo (current): modules are sourced from get_repo_root() at HEAD.
#   All environments share the same module code. Safe for small teams.
# - Registry (future): change source_base to a Terraform registry URL and
#   pin each module to a semver tag. Enables independent env promotion.
#
# To migrate a module to versioned releases:
#   1. Publish the module to a registry (or use git tags)
#   2. Update the source below to the registry URL with a version pin
#   3. Promote versions through environments: dev → staging → prod

locals {
  source_base = "${get_repo_root()}/infra/modules"

  module_source = {
    # Core infrastructure
    resource_group = "${local.source_base}/azure//resource_group"
    networking     = "${local.source_base}/azure//networking"
    naming         = "${local.source_base}/azure//naming"
    client_config  = "${local.source_base}/azure//client_config"

    # Compute
    aks_core       = "${local.source_base}/azure//aks_core"
    aks_identity   = "${local.source_base}/azure//identities"
    aks_node_pools = "${local.source_base}/azure//aks_node_pools"

    # Storage & secrets
    key_vault         = "${local.source_base}/azure//key_vault"
    storage_account   = "${local.source_base}/azure//storage_account"
    storage_container = "${local.source_base}/azure//storage_container"
    storage_roles     = "${local.source_base}/azure//storage_roles"

    # Networking (CDN / Front Door)
    frontdoor_profile      = "${local.source_base}/azure//frontdoor_profile"
    frontdoor_endpoint     = "${local.source_base}/azure//frontdoor_endpoint"
    frontdoor_private_link = "${local.source_base}/azure//frontdoor_private_link"

    # Observability
    log_analytics       = "${local.source_base}/azure//log_analytics"
    monitor_workspace   = "${local.source_base}/azure//monitor_workspace"
    managed_grafana     = "${local.source_base}/azure//managed_grafana"
    prometheus_dcr      = "${local.source_base}/azure//prometheus_dcr"
    monitor_alerts      = "${local.source_base}/azure//monitor_alerts"
    diagnostic_settings = "${local.source_base}/azure//diagnostic_settings"

    # Composite stacks
    stack_base = "${local.source_base}/azure//stack_base"

    # DNS & identity
    private_dns = "${local.source_base}/azure//private_dns"
    identities  = "${local.source_base}/azure//identities"
    container_registry = "${local.source_base}/azure//container_registry"

    # Cloud-agnostic (Kubernetes add-ons)
    cilium           = "${local.source_base}/cilium"
    argocd           = "${local.source_base}/argocd"
    argocd_bootstrap = "${local.source_base}/argocd-bootstrap"
  }

  # Helm chart version pins — single source of truth across environments
  helm_versions = {
    cilium           = "1.17.2"
    argocd           = "7.8.13"
    cert_manager     = "1.17.1"
    external_dns     = "1.16.1"
    external_secrets = "0.14.3"
  }
}
