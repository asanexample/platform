# ---------------------------------------------------------------------------------------------------------------------
# SHARED BASE CONFIGURATION — GCP
# ---------------------------------------------------------------------------------------------------------------------
# Include this file in every module-level terragrunt.hcl to eliminate boilerplate.
#
# Usage:
#   include "base" {
#     path   = find_in_parent_folders("gcp/_base.hcl")
#     expose = true
#   }
#
# Then reference values as: include.base.locals.<name>
#
# CONFIG HIERARCHY (broadest → narrowest scope):
#   1. Root         infra/root.hcl              Remote state, providers, global tags
#   2. Cloud        infra/live/gcp/common.hcl          Cloud-wide defaults (workload, project tags)
#   3. Environment  infra/live/gcp/{env}/env.hcl       Project ID, env tags
#   4. Region       infra/live/gcp/{env}/{region}/     region.hcl (region info), network.hcl (CIDRs)
#   5. Defaults     infra/live/gcp/_envcommon/*.hcl     Module defaults shared across environments
#   6. Module       infra/live/gcp/{env}/{region}/{module}/terragrunt.hcl   Final overrides
#
# At each level, later layers override earlier ones for tags and inputs.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # ---------------------------------------------------------------------------
  # Load hierarchical configuration files
  # ---------------------------------------------------------------------------
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))

  # Flat merge of all config layers (useful for ad-hoc lookups)
  all_vars = merge(
    local.common_vars.locals,
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
  )

  # ---------------------------------------------------------------------------
  # Commonly used scalars
  # ---------------------------------------------------------------------------
  env         = local.env_vars.locals.environment
  workload    = local.common_vars.locals.workload
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  project_id  = local.env_vars.locals.project_id

  # ---------------------------------------------------------------------------
  # Composed tags/labels: common → environment → region (later layers win)
  # ---------------------------------------------------------------------------
  tags = merge(
    local.common_vars.locals.tags,
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags,
  )

  # ---------------------------------------------------------------------------
  # Safety validations
  # ---------------------------------------------------------------------------

  # Extract environment from directory structure for cross-check.
  # path_relative_to_include() from _base.hcl → calling module yields "{env}/{region}/{module}".
  _path_parts = split("/", path_relative_to_include())
  _path_env   = local._path_parts[0]

  # 1. Directory path must match the configured environment
  _assert_env_path = (
    local._path_env == local.env
    ? true
    : tobool("SAFETY: directory '${local._path_env}' does not match env.hcl environment '${local.env}'")
  )

  # 2. GCP project ID must match the expected value for this environment
  _expected_project = lookup(
    local.common_vars.locals.environment_project_map,
    local.env,
    null
  )
  _assert_project = (
    local._expected_project == null ||
    local._expected_project == local.env_vars.locals.project_id
    ? true
    : tobool("SAFETY: env '${local.env}' expects project '${local._expected_project}' but env.hcl has '${local.env_vars.locals.project_id}'")
  )
}
