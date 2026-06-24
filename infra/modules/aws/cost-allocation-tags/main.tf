# ---------------------------------------------------------------------------
# Cost-allocation tags
# ---------------------------------------------------------------------------
# Activates user-defined AWS cost-allocation tags so the Cost & Usage Report and
# Cost Explorer can break spend down by these keys (e.g. per-team, per-environment).
# The prerequisite for true per-team cloud cost — #668 / ADR-079 D4 (P11 part 2).
#
# Notes:
#   * Payer/management account only — activation is an organization-level billing setting.
#   * Forward-only with a ~24h lag: spend is attributed by the tag from activation
#     onward, NOT retroactively. Activate early so data accrues before the consumers
#     (CUR → Athena → OpenCost cloudCost / Grafana) are built.
#   * The tag keys must already appear on resources for AWS to surface them. `Team`
#     and `Environment` are applied platform-wide via the Terragrunt tag hierarchy.

resource "aws_ce_cost_allocation_tag" "this" {
  for_each = var.create ? toset(var.tag_keys) : toset([])

  tag_key = each.value
  status  = "Active"
}
