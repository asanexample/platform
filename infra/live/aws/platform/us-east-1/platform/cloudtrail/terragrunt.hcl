include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cloudtrail
}

inputs = {
  create     = true
  trail_name = "${include.base.locals.env}-${include.base.locals.region_abbv}-secrets-audit"

  data_event_selectors = [
    {
      name          = "secrets-manager-data-events"
      resource_type = "AWS::SecretsManager::Secret"
      resource_arns = ["arn:aws:secretsmanager:${include.base.locals.region}:${include.base.locals.account_id}:secret:platform/"]
    },
  ]

  enable_cloudwatch     = true
  enable_secrets_alarms = true
  log_retention_days    = 90

  tags = include.base.locals.tags
}
