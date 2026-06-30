# Platform cost alerting in the payer/management account — AWS Budgets + Cost Anomaly Detection → SNS →
# Slack (AWS Chatbot) + email (ADR-092, #1054). The platform team's own bill-level cost signal; per-team
# budgets ride ADR-091's Mimir-ruler, not this. Budgets/Anomaly/Cost Explorer are payer-account billing
# services, so this lives at mgmt/global (us-east-1).

include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cost_monitoring
}

inputs = {
  create = true

  alert_emails = [include.base.locals.admin_email]

  # Two monthly tripwires (AWS Budgets free tier = 2). Amounts set from May–Jun 2026 actuals + headroom
  # (platform ~$568, preprod ~$677 in June; the consolidated bill ran ~$1.25k). Tune as the footprint settles.
  budgets = {
    "platform-consolidated-monthly" = {
      limit_usd = 2000
    }
    "platform-account-monthly" = {
      limit_usd       = 800
      linked_accounts = [include.base.locals.account_ids["platform"]]
    }
  }

  # IMMEDIATE anomaly alert when a service's detected impact crosses this. Start conservative; the nightly
  # park down/up swing can read as anomalous, so calibrate before treating these as urgent (see runbook).
  anomaly_threshold_usd = 50

  # Subscribe to the account's auto-created default SERVICE monitor — AWS permits only one dimensional
  # monitor per account, so we don't create a second (it 400s with "Limit exceeded"). See the runbook.
  existing_monitor_arn = "arn:aws:ce::851725353202:anomalymonitor/a147a6bf-b817-44a5-b005-9e97a3e8b293"

  # Slack delivery via AWS Chatbot. Empty until the one-time workspace authorization is done (then email-only).
  # Capture the workspace + channel IDs per docs/runbooks/cost-alerting.md.
  slack_team_id    = ""
  slack_channel_id = ""
}
