# cost-monitoring

Account/bill-level cost alerting for the platform's **own** spend — AWS Budgets + AWS Cost Anomaly
Detection, delivered to Slack (via AWS Chatbot) and email through a dedicated SNS topic. The platform-team
half of ADR-092 (#1054); the proactive version of the CloudWatch `$356/mo` control-plane-logging fire-drill.

**Payer/management account only.** Budgets, Cost Anomaly Detection, and Cost Explorer are organization-level
billing services that live in the payer account (851725353202). Deploy from `mgmt/global/`.

This is **not** the tenant owner-routing fabric: per-team budget alerts ride ADR-091's Mimir-ruler →
owner-routing (ADR-084); platform/account cost is owned by the platform team and delivered here.

## Delivery

```text
AWS Budgets ─┐
             ├─► SNS topic (platform-cost-alerts) ─┬─► AWS Chatbot ─► Slack #cost
Cost Anomaly ┘   (unencrypted — see note)          └─► email
```

The topic is intentionally **not** SSE-KMS encrypted: the AWS-managed `alias/aws/sns` key can't grant the
`budgets.amazonaws.com` / `costalerts.amazonaws.com` publishers, and AWS Chatbot can't read a managed-key
topic. Payloads are low-sensitivity (account ids + dollar amounts). A customer-managed CMK is the #118 upgrade.

## One-time manual prerequisite (Slack)

AWS Chatbot needs the Slack workspace authorized once before Terraform can create the channel configuration:

1. AWS console → **Amazon Q Developer in chat applications** (formerly AWS Chatbot) → **Configure a Slack client**
   → authorize the workspace.
2. Create/choose the `#cost` Slack channel and invite the **AWS** app to it.
3. Capture the **workspace (team) ID** and **channel ID** → set `slack_team_id` / `slack_channel_id`.

Leave `slack_team_id = ""` to ship email-only; the Chatbot resources are gated off until it's set. The email
subscriber must also confirm the SNS subscription email AWS sends.

See `docs/runbooks/cost-alerting.md` for the full procedure + threshold tuning.

## Budgets free tier

The first two budgets are free; each additional budget costs $0.02/day. Under the no-spend mandate keep
`budgets` to **≤ 2** (a consolidated total + the platform account is the recommended pair). Cost Anomaly
Detection and AWS Chatbot are free.
