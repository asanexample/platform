# cost-allocation-tags

Activates user-defined AWS **cost-allocation tags** in the payer/management account so the Cost & Usage
Report (CUR) and Cost Explorer can attribute spend by these keys — the prerequisite for true per-team /
per-environment cloud cost (#668 / [ADR-079](../../../../docs/adrs/079-cloud-resource-monitoring-scope.md) D4,
observability P11 part 2).

> **Forward-only, ~24h lag.** Activation attributes spend from the moment it takes effect onward, **not
> retroactively**. Activate early so data is already accruing when the consumers (CUR → Athena → OpenCost
> `cloudCost` / Grafana) are built. The tag keys must already appear on resources for AWS to surface them —
> `Team` and `Environment` are applied platform-wide via the Terragrunt tag hierarchy.

This unit is **management-account-only** (Cost Explorer is an organization-level, us-east-1 billing service)
and is independent of the rest of #668 — it can be applied on its own.

| Input | Description | Default |
|-------|-------------|---------|
| `create` | Whether to activate the tags. | `true` |
| `tag_keys` | Tag keys to activate (must already exist on resources). | `[]` |

| Output | Description |
|--------|-------------|
| `active_tag_keys` | The tag keys activated. |
