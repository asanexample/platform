# Runbook: Platform cost alerting (AWS Budgets + Cost Anomaly Detection)

Bill-level cost alerting for the platform's **own** spend — the platform-team half of ADR-092 (#1054). AWS
Budgets + Cost Anomaly Detection publish to a dedicated SNS topic in the **management/payer** account
(851725353202), which fans out to a Slack channel (via AWS Chatbot) and email.

- **Module:** `infra/modules/aws/cost-monitoring`
- **Unit:** `infra/live/aws/mgmt/global/cost-monitoring/` (apply with `AWS_PROFILE=management`)
- **Not** the tenant path: per-team budget alerts ride ADR-091's Mimir-ruler → owner-routing (ADR-084). This is
  account/shared cost, owned by the platform team.

## One-time prerequisite: authorize AWS Chatbot in Slack

The `aws_chatbot_slack_channel_configuration` resource can only be created **after** the Slack workspace is
authorized — this is a manual, one-time console step (no API):

1. AWS console (management account) → **Amazon Q Developer in chat applications** (formerly AWS Chatbot) →
   **Configure a client** → **Slack** → authorize the workspace.
2. In Slack, create (or pick) the `#cost` channel and invite the **AWS** app: `/invite @AWS`.
3. Capture the IDs:
   - **Workspace (team) ID** — shown in the Chatbot console after authorization (starts with `T…`).
   - **Channel ID** — in Slack, right-click the channel → *View channel details* → bottom of the dialog
     (starts with `C…`).
4. Set them on the unit and re-apply:

   ```hcl
   slack_team_id    = "T0XXXXXXX"
   slack_channel_id = "C0XXXXXXX"
   ```

   Until `slack_team_id` is set the Chatbot resources are gated off and delivery is **email-only** — that's a
   valid state to ship in.

## Cost Anomaly Detection monitor

AWS permits only **one** dimensional (SERVICE) anomaly monitor per account and auto-creates a
`Default-Services-Monitor` the first time Cost Anomaly Detection is used. The module therefore **subscribes to
the existing monitor** (`existing_monitor_arn`) rather than creating a second one — creating another fails with
`ValidationException: Limit exceeded on dimensional spend monitor creation`. Find the ARN with:

```bash
AWS_PROFILE=management aws ce get-anomaly-monitors \
  --query 'AnomalyMonitors[?MonitorType==`DIMENSIONAL`].MonitorArn' --output text
```

Leave `existing_monitor_arn` empty only in an account that has no default monitor yet.

## Confirm the email subscription

After the first apply, AWS sends a *Subscription Confirmation* email to each `alert_emails` address. The
recipient must click **Confirm subscription** or no email alerts arrive (`aws sns list-subscriptions-by-topic`
shows `PendingConfirmation` until then).

## Tuning

- **Budget amounts** (`budgets` in the unit) — start from recent actuals plus headroom
  (`aws ce get-cost-and-usage --time-period Start=…,End=… --granularity MONTHLY --metrics UnblendedCost
  --group-by Type=DIMENSION,Key=LINKED_ACCOUNT`). Keep to **≤ 2 budgets** (AWS Budgets free tier); each extra
  budget is $0.02/day.
- **Anomaly threshold** (`anomaly_threshold_usd`) — the absolute total-impact (USD) that triggers an IMMEDIATE
  alert. **Calibration note:** the nightly cluster park (`platctl down`/`up`) produces a large, *expected*
  down/up cost swing that ML anomaly detection may flag. Start conservative, treat early alerts as warnings, and
  raise the threshold (or add a dimension filter) until the signal is clean before treating these as urgent.

## Verify (post-apply)

```bash
AWS_PROFILE=management aws budgets describe-budgets --account-id 851725353202 \
  --query 'Budgets[].{Name:BudgetName,Limit:BudgetLimit.Amount}'
AWS_PROFILE=management aws ce get-anomaly-monitors --query 'AnomalyMonitors[].MonitorName'
# Smoke-test delivery end to end:
AWS_PROFILE=management aws sns publish --topic-arn \
  arn:aws:sns:us-east-1:851725353202:platform-cost-alerts --subject 'cost test' --message 'delivery test'
# → expect the message in #cost (if Chatbot configured) and in the confirmed email inbox.
```

Budget and anomaly alerts then flow automatically; no further action.
