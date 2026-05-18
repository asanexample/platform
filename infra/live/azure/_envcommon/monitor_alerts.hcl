# Common configuration for Azure Monitor Alerts across environments

terraform {
  source = "${get_repo_root()}/infra/modules/azure//monitor_alerts"
}

locals {
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region           = local.region_vars.locals.region
  common_vars      = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_tags      = local.common_vars.locals.tags
}

inputs = {
  location = local.region

  action_groups = {
    platform-critical = {
      short_name        = "plat-crit"
      email_receivers   = []
      webhook_receivers = []
    }
    platform-warning = {
      short_name        = "plat-warn"
      email_receivers   = []
      webhook_receivers = []
    }
  }

  tags = merge(local.common_tags, {
    "ResourceType" = "MonitorAlerts"
    "Component"    = "Monitoring"
  })
}
