# ---------------------------------------------------------------------------
# Platform cost monitoring — AWS Budgets + Cost Anomaly Detection → SNS → Slack/email
# ---------------------------------------------------------------------------
# Account/bill-level cost alerting for the platform's OWN spend (ADR-092, #1054).
# Payer/management account only: Budgets, Cost Anomaly Detection, and Cost
# Explorer are organization-level billing services that live in the payer.
#
# This is the platform team's own cost signal — deliberately NOT the tenant
# owner-routing fabric. Owner-routing (ADR-084) is in-cluster Alertmanager and
# resolves tenant teams; per-team budgets ride ADR-091's Mimir-ruler. Here the
# owner is the platform team, so delivery is a dedicated SNS topic → AWS Chatbot
# (Slack) + email.

data "aws_caller_identity" "current" {}

locals {
  create_chatbot = var.create && var.slack_team_id != ""

  # Subscribe to the account's existing (default) dimensional monitor when given;
  # otherwise the one this module creates. Null when disabled.
  monitor_arn = var.create ? (var.existing_monitor_arn != "" ? var.existing_monitor_arn : aws_ce_anomaly_monitor.services[0].arn) : null

  # Alert at 80% actual, 100% actual, and 100% forecasted month-end spend.
  budget_notifications = {
    actual_80      = { threshold = 80, type = "PERCENTAGE", notification_type = "ACTUAL" }
    actual_100     = { threshold = 100, type = "PERCENTAGE", notification_type = "ACTUAL" }
    forecasted_100 = { threshold = 100, type = "PERCENTAGE", notification_type = "FORECASTED" }
  }
}

# ---------------------------------------------------------------------------
# SNS delivery topic
# ---------------------------------------------------------------------------
# Deliberately NOT SSE-KMS encrypted. The AWS-managed key (alias/aws/sns) cannot
# grant the budgets.amazonaws.com / costalerts.amazonaws.com service principals
# publish access (its key policy isn't editable), and AWS Chatbot cannot
# subscribe to a managed-key-encrypted topic. Cost-alert payloads are
# low-sensitivity (account ids + dollar amounts). A customer-managed CMK whose
# key policy admits those principals + Chatbot is the #118 encryption-upgrade
# path; until then an unencrypted topic is the correct, working choice.
resource "aws_sns_topic" "cost_alerts" {
  count = var.create ? 1 : 0

  name = var.topic_name
  tags = var.tags
}

# Budgets and Cost Anomaly Detection publish via the TOPIC policy (not their own
# identity) — both are AWS-managed services. Scoped with aws:SourceAccount to the
# payer account (confused-deputy guard). AWS validates this at subscription
# create, so the budget/anomaly resources depend on it.
data "aws_iam_policy_document" "cost_alerts" {
  count = var.create ? 1 : 0

  statement {
    sid    = "AllowCostServicesPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cost_alerts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "cost_alerts" {
  count = var.create ? 1 : 0

  arn    = aws_sns_topic.cost_alerts[0].arn
  policy = data.aws_iam_policy_document.cost_alerts[0].json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.create ? toset(var.alert_emails) : toset([])

  topic_arn = aws_sns_topic.cost_alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# ---------------------------------------------------------------------------
# AWS Budgets
# ---------------------------------------------------------------------------
# Monthly cost tripwires. AWS Budgets are free for the first two, then
# $0.02/budget/day — keep var.budgets to <= 2 under the no-spend mandate.
resource "aws_budgets_budget" "this" {
  for_each = var.create ? var.budgets : {}

  name         = each.key
  budget_type  = "COST"
  limit_amount = tostring(each.value.limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Optional scope to one or more linked accounts; omitted = consolidated total.
  dynamic "cost_filter" {
    for_each = each.value.linked_accounts == null ? [] : [each.value.linked_accounts]
    content {
      name   = "LinkedAccount"
      values = cost_filter.value
    }
  }

  dynamic "notification" {
    for_each = local.budget_notifications
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.threshold
      threshold_type            = notification.value.type
      notification_type         = notification.value.notification_type
      subscriber_sns_topic_arns = [aws_sns_topic.cost_alerts[0].arn]
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

# ---------------------------------------------------------------------------
# Cost Anomaly Detection
# ---------------------------------------------------------------------------
# An ML monitor over the consolidated bill, dimensioned by SERVICE so a spike in
# any one service (the EKS-control-plane-logging $356/mo fire-drill is the
# canonical example) surfaces on its own. Org-wide from the payer.
#
# AWS allows only ONE dimensional (SERVICE) monitor per account, and it
# auto-creates a "Default-Services-Monitor" the first time Cost Anomaly
# Detection is touched. So by default we SUBSCRIBE to that existing monitor
# (var.existing_monitor_arn) rather than create a second one (which fails with
# "Limit exceeded on dimensional spend monitor creation"). Leave the var empty
# only in an account that has no default monitor yet.
resource "aws_ce_anomaly_monitor" "services" {
  count = var.create && var.existing_monitor_arn == "" ? 1 : 0

  name              = "${var.name_prefix}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = var.anomaly_monitor_dimension
}

# IMMEDIATE alerts (SNS-only frequency) above an absolute-impact threshold. The
# email/Slack fan-out happens off the topic. depends_on the topic policy because
# AWS test-publishes when the subscription is created.
resource "aws_ce_anomaly_subscription" "this" {
  count = var.create ? 1 : 0

  name             = "${var.name_prefix}-immediate"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [local.monitor_arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts[0].arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_threshold_usd)]
    }
  }

  depends_on = [aws_sns_topic_policy.cost_alerts]
}

# ---------------------------------------------------------------------------
# Chatbot (Slack) delivery
# ---------------------------------------------------------------------------
# Gated on slack_team_id — requires the one-time manual authorization of the AWS
# Chatbot app in the Slack workspace (see README). Notifications need no AWS
# read access, but Chatbot requires both a role and a guardrail; the guardrail
# is pinned read-only (it defaults to AdministratorAccess otherwise).
data "aws_iam_policy_document" "chatbot_assume" {
  count = local.create_chatbot ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  count = local.create_chatbot ? 1 : 0

  name               = "${var.name_prefix}-chatbot"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume[0].json
  tags               = var.tags
}

resource "aws_chatbot_slack_channel_configuration" "cost" {
  count = local.create_chatbot ? 1 : 0

  configuration_name = var.name_prefix
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id
  sns_topic_arns     = [aws_sns_topic.cost_alerts[0].arn]

  guardrail_policy_arns = var.chatbot_guardrail_policy_arns
  logging_level         = "ERROR"

  tags = var.tags
}
