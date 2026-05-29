include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.route53
}

inputs = {
  create = true
  # Subdomain delegated from platform's aws.refplat.org zone (via route53-delegation unit)
  domain_name   = "preprod.aws.refplat.org"
  force_destroy = true # Allow Terragrunt to destroy zone even if it contains records

  # CAA records restrict certificate issuance to Let's Encrypt only
  caa_records = [
    "0 issue \"letsencrypt.org\"",
    "0 issuewild \"letsencrypt.org\"",
    "0 iodef \"mailto:${include.base.locals.admin_email}\"", # Certificate violation notifications
  ]

  tags = include.base.locals.tags
}
