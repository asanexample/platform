# ---------------------------------------------------------------------------
# Alertmanager → SNS publish; AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "alertmanager_trust" {
  count = local.create_sns ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alertmanager" {
  count = local.create_sns ? 1 : 0

  name_prefix        = "${var.cluster_name}-am-sns-"
  assume_role_policy = data.aws_iam_policy_document.alertmanager_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "alertmanager_sns" {
  count = local.create_sns ? 1 : 0

  name = "sns-publish"
  role = aws_iam_role.alertmanager[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.alerts_topic_arn]
      },
      {
        # The alerts topic is SSE-KMS encrypted (AWS-managed alias/aws/sns key),
        # so publishing requires data-key access. The managed key's ARN isn't
        # known here; scope to SNS via kms:ViaService so the grant is only usable
        # for SNS publishes in this region.
        Sid      = "EncryptAlerts"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = ["*"]
        Condition = {
          StringEquals = { "kms:ViaService" = "sns.${var.aws_region}.amazonaws.com" }
        }
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "alertmanager" {
  count = local.create_sns ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.alertmanager_sa
  role_arn        = aws_iam_role.alertmanager[0].arn
  tags            = var.tags
}
# ---------------------------------------------------------------------------
# Slack webhook for Alertmanager — External Secret synced from AWS Secrets Manager.
# Mounted into Alertmanager via alertmanagerSpec.secrets; the Slack receiver reads it through
# api_url_file, so the webhook URL never enters Terraform state or the helm values. The SM secret is
# created manually (the URL is generated in Slack), JSON property "url".
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "alertmanager_slack_webhook" {
  count = local.slack_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-slack-webhook"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "alertmanager-slack-webhook", creationPolicy = "Owner" }
      data = [{
        secretKey = "url"
        remoteRef = { key = var.slack_webhook_secret_name, property = "url" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# ---------------------------------------------------------------------------
# PagerDuty routing key for Alertmanager — External Secret synced from AWS Secrets Manager.
# Mounted via alertmanagerSpec.secrets; the PagerDuty receiver reads it through routing_key_file. The SM
# secret is created manually (the key is generated in PagerDuty), JSON property "routingKey".
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "alertmanager_pagerduty" {
  count = local.pagerduty_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-pagerduty"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "alertmanager-pagerduty", creationPolicy = "Owner" }
      data = [{
        secretKey = "routingKey"
        remoteRef = { key = var.pagerduty_routing_key_secret_name, property = "routingKey" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# Dead-man's switch ping URL, synced from Secrets Manager. The SM secret MUST exist before this is enabled
# (creationPolicy Owner + the Alertmanager mount) — else the ExternalSecret can't sync and Alertmanager fails
# to start. See the healthchecks_ping_url_secret_name variable's activation note.
resource "kubernetes_manifest" "alertmanager_healthchecks" {
  count = local.deadman_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "alertmanager-healthchecks"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = "alertmanager-healthchecks", creationPolicy = "Owner" }
      data = [{
        secretKey = "pingUrl"
        remoteRef = { key = var.healthchecks_ping_url_secret_name, property = "pingUrl" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}
