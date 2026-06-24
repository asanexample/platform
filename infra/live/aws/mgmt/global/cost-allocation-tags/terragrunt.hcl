# Activate AWS cost-allocation tags in the payer/management account so the CUR / Cost Explorer can break
# spend down by team and environment — the per-team-true-cost prerequisite (#668 / ADR-079 D4, P11 part 2).
# Activation is forward-only (~24h lag), so this lands ahead of the rest of #668 to start accruing data.

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cost_allocation_tags
}

inputs = {
  create = true

  # Keys with real cost-breakdown value (constant tags like CostCenter/Project/Owner add no dimension):
  #   Team        — per-team spend (the #668 goal; team-owned resources override the default, #61)
  #   Environment — platform / preprod / prod spend
  # Both are applied platform-wide via the Terragrunt tag hierarchy (common.hcl / env.hcl).
  tag_keys = ["Team", "Environment"]
}
