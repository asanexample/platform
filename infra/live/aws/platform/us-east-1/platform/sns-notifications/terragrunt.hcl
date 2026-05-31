include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.sns_notifications
}

inputs = {
  create     = true
  topic_name = "platform-alerts"

  # NOTE: each email subscription must be CONFIRMED via the email AWS sends before notifications flow.
  alert_emails = [include.base.locals.admin_email]

  tags = include.base.locals.tags
}
