# ---------------------------------------------------------------------------
# Platform alert notifications — SNS topic + email subscriptions
# ---------------------------------------------------------------------------
# Minimal: publishers (e.g. the observability Alertmanager IRSA role, Falco's
# falcosidekick) are granted sns:Publish via their OWN IAM identity policy on
# topic_arn — kept off the topic resource policy so this module doesn't depend
# on those roles (avoids a dependency cycle). Same-account publish works on the
# default topic policy.

resource "aws_sns_topic" "this" {
  count = var.create ? 1 : 0

  name = var.topic_name
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.create ? toset(var.alert_emails) : toset([])

  topic_arn = aws_sns_topic.this[0].arn
  protocol  = "email"
  endpoint  = each.value
}
