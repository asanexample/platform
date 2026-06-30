# True cloud cost in the payer/management account — Cost & Usage Report → S3 → Glue → Athena, attributed by
# the activated Team cost-allocation tag (#668 / ADR-079 D4, P11 part 2). The authoritative bill behind the
# platform FinOps practice (ADR-092). CUR is us-east-1-only and org-wide from the payer, so this lives at
# mgmt/global. Consumed cross-account by OpenCost cloudCost on the platform hub (Phase 2a).

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cost_export
}

inputs = {
  create = true

  # Cross-account read role. Trust the platform account for now (the OpenCost consumer lives there); the actual
  # assume is double-gated by OpenCost's own identity policy. Phase 2a tightens this to the specific OpenCost
  # pod-identity role ARN once it exists.
  reader_trusted_principal_arns = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:root"]
}
