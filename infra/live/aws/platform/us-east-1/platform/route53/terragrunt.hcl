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
  create        = true
  domain_name   = "aws.refplat.org"
  force_destroy = true

  caa_records = [
    "0 issue \"letsencrypt.org\"",
    "0 issuewild \"letsencrypt.org\"",
    "0 iodef \"mailto:josh@deeden.org\"",
  ]

  tags = include.base.locals.tags
}
