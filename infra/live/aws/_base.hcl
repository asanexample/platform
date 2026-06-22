# ---------------------------------------------------------------------------------------------------------------------
# SHARED BASE CONFIGURATION
# ---------------------------------------------------------------------------------------------------------------------
# Include this file in every module-level terragrunt.hcl to eliminate boilerplate.
#
# Usage:
#   include "base" {
#     path   = find_in_parent_folders("aws/_base.hcl")
#     expose = true
#   }
#
# Then reference values as: include.base.locals.<name>
#
# CONFIG HIERARCHY (broadest -> narrowest scope):
#   1. Root         infra/root.hcl              Remote state, providers, global tags
#   2. Cloud        infra/live/aws/common.hcl          Cloud-wide defaults (workload, project tags)
#   3. Environment  infra/live/aws/{env}/env.hcl       Account ID, env tags, policies
#   4. Region       infra/live/aws/{env}/{region}/     region.hcl (region info), network.hcl (CIDRs)
#   5. Defaults     infra/live/aws/_envcommon/*.hcl    Module defaults shared across environments
#   6. Module       infra/live/aws/{env}/{region}/{module}/terragrunt.hcl   Final overrides
#
# At each level, later layers override earlier ones for tags and inputs.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Load hierarchical configuration files
  # ---------------------------------------------------------------------------
  env_vars      = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars   = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars  = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  workload_vars = read_terragrunt_config(find_in_parent_folders("workload.hcl"))
  common_vars   = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  version_vars  = read_terragrunt_config(find_in_parent_folders("aws/_versions.hcl"))

  # Flat merge of all config layers (useful for ad-hoc lookups)
  all_vars = merge(
    local.common_vars.locals,
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.workload_vars.locals,
  )

  # ---------------------------------------------------------------------------
  # Commonly used scalars
  # ---------------------------------------------------------------------------
  env             = local.env_vars.locals.environment
  workload        = local.workload_vars.locals.workload
  compliance_tier = local.workload_vars.locals.compliance_tier
  region          = local.region_vars.locals.region
  region_abbv     = local.region_vars.locals.region_abbv
  account_id      = local.env_vars.locals.account_id

  # ---------------------------------------------------------------------------
  # Cost / environment-profile toggles (defaults in common.hcl; env.hcl may override).
  # See docs/plans/cost-optimized-dev-rebuild.md.
  # ---------------------------------------------------------------------------
  # One switch (cost_profile) sets the bundle; an explicit per-knob override wins over the preset.
  cost_profile = try(local.all_vars.cost_profile, "dev")
  _cost_profiles = {
    dev  = { high_availability = false, single_az_nodes = true, enable_mimir = false, enable_loki = false, enable_log_pipeline = false, enable_tempo = false, enable_trace_pipeline = false }
    prod = { high_availability = true, single_az_nodes = false, enable_mimir = true, enable_loki = true, enable_log_pipeline = true, enable_tempo = true, enable_trace_pipeline = true }
  }
  _profile = local._cost_profiles[local.cost_profile]

  high_availability     = try(local.all_vars.high_availability, local._profile.high_availability)
  single_az_nodes       = try(local.all_vars.single_az_nodes, local._profile.single_az_nodes)
  enable_mimir          = try(local.all_vars.enable_mimir, local._profile.enable_mimir)
  enable_loki           = try(local.all_vars.enable_loki, local._profile.enable_loki)
  enable_log_pipeline   = try(local.all_vars.enable_log_pipeline, local._profile.enable_log_pipeline)
  enable_tempo          = try(local.all_vars.enable_tempo, local._profile.enable_tempo)
  enable_trace_pipeline = try(local.all_vars.enable_trace_pipeline, local._profile.enable_trace_pipeline)
  node_arch             = try(local.all_vars.node_arch, "arm64")

  # EKS control-plane log types vended to CloudWatch. Defaults to [] (OFF) — the `audit`/`api` streams are billed
  # at the vended-logs ingestion rate and, driven by the GitOps controllers' constant apiserver traffic, ran
  # ~$700/mo across both dev clusters. Dev doesn't need them. Re-enable for prod/regulated by setting
  # `control_plane_log_types = ["api","audit","authenticator","controllerManager","scheduler"]` in that env's
  # env.hcl. (Cost is intrinsic to vending — retention/filtering can't reduce it; the only lever is fewer types.)
  control_plane_log_types = try(local.all_vars.control_plane_log_types, [])

  # ---------------------------------------------------------------------------
  # Module sources and version pins (from _versions.hcl)
  # ---------------------------------------------------------------------------
  module_source = local.version_vars.locals.module_source
  helm_versions = local.version_vars.locals.helm_versions

  # ---------------------------------------------------------------------------
  # Secrets (via common.hcl -> SOPS secrets.enc.yaml chain, ADR-066)
  # ---------------------------------------------------------------------------
  account_ids    = local.common_vars.locals.account_ids
  admin_email    = local.common_vars.locals.admin_email
  account_emails = local.common_vars.locals.account_emails

  # Org/resource name prefix (e.g. tenant bucket names). See common.hcl.
  org_name = local.common_vars.locals.org_name

  # ---------------------------------------------------------------------------
  # IAM role ARNs
  # ---------------------------------------------------------------------------
  deployer_role_arn = "arn:aws:iam::${local.account_id}:role/PlatformDeployer"

  # ---------------------------------------------------------------------------
  # Composed tags: common -> environment -> region -> workload (later layers win)
  # ---------------------------------------------------------------------------
  tags = merge(
    local.common_vars.locals.tags,
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags,
    local.workload_vars.locals.workload_tags,
  )

  # ---------------------------------------------------------------------------
  # Safety validations
  # ---------------------------------------------------------------------------

  # Extract environment from directory structure for cross-check.
  # path_relative_to_include() from _base.hcl -> calling module yields "{env}/{region}/{module}".
  _path_parts = split("/", path_relative_to_include())
  _path_env   = local._path_parts[0]

  # 1. Directory path must match the configured environment
  _assert_env_path = (
    local._path_env == local.env
    ? true
    : tobool("SAFETY: directory '${local._path_env}' does not match env.hcl environment '${local.env}'")
  )

  # 2. Account ID must match the expected value for this environment
  _expected_account = lookup(
    local.common_vars.locals.environment_account_map,
    local.env,
    null
  )
  _assert_account = (
    local._expected_account == null ||
    local._expected_account == local.env_vars.locals.account_id
    ? true
    : tobool("SAFETY: env '${local.env}' expects account '${local._expected_account}' but env.hcl has '${local.env_vars.locals.account_id}'")
  )
}
